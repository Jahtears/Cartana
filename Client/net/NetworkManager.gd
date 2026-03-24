extends Node

signal connected()
signal disconnected(code: int, reason: String)
signal connection_lost()
signal connection_restored()
signal reconnect_failed()
signal server_closed(server_reason: String, close_code: int, raw_reason: String)
signal response(rid: String, type: String, ok: bool, data: Dictionary, error: Dictionary)
signal evt(type: String, data: Dictionary)

const DEFAULT_TIMEOUT_SEC := 10.0
const MAX_RETRIES := 3
const MAX_QUEUE_SIZE := 100

const PENDING_ACTIVITY_TIMEOUT_MS := 15000
const PENDING_ACTIVITY_PROBE_TIMEOUT_MS := 4000
const PENDING_ACTIVITY_TIMEOUT_REASON := "Connection lost (no server response)"

const RECONNECT_INITIAL_DELAY_SEC := 1.0
const RECONNECT_MAX_DELAY_SEC := 30.0
const RECONNECT_BACKOFF_MULTIPLIER := 1.5

const DISCONNECT_REASON_CLOSE := "close"
const DISCONNECT_REASON_LOGOUT := "logout"
const DISCONNECT_REASON_RECONNECT_MAX := "Max reconnect attempts exceeded"

const SERVER_CLOSE_REASON_PREFIX := "SERVER_"
const LOCAL_ERROR_MESSAGE_CODE := "POPUP_TECH_ERROR_GENERIC"

const FORCED_WSS_URL := "wss://192.168.1.40/ws"
const TLS_ROOT_CERT_PATH := "res://certs/caddy-root.crt"

enum RequestPriority { LOW = 0, NORMAL = 5, HIGH = 8, CRITICAL = 10 }
enum ConnectionState { IDLE, CONNECTING, CONNECTED, RECOVERING }
enum DisconnectClass { VOLUNTARY, SERVER_CLOSED_EXPLICIT, CLIENT_LOST }

var _ws := WebSocketPeer.new()
var _url := ""
var _rid_counter: int = 0
var server_clock_offset_ms: int = 0
var _was_open: bool = false
var _last_rx_ms: int = 0
var _connect_in_flight: bool = false

var _request_queue: Array = []
var _pending_results: Dictionary = {}
var _pending_requests: Dictionary = {}

var _reconnect_timer: Timer = null
var _reconnect_delay_sec: float = RECONNECT_INITIAL_DELAY_SEC
var _reconnect_attempts: int = 0
var _max_reconnect_attempts: int = 10

var _auth_credentials: Dictionary = {}
var _is_authenticated: bool = false
var _login_in_flight: bool = false
var _allow_reconnect: bool = true
var _disconnect_reason: String = ""
var _client_connection_lost: bool = false
var _connection_state: int = ConnectionState.IDLE

var _activity_probe_in_flight: bool = false
var _activity_probe_started_ms: int = 0
var _activity_probe_rid: String = ""
var _activity_probe_ignore_rid: String = ""

func _ready() -> void:
    pass

func _build_tls_client_options() -> TLSOptions:
    if not _url.begins_with("wss://"):
        return null
    if OS.has_feature("web"):
        return null

    if not FileAccess.file_exists(TLS_ROOT_CERT_PATH):
        push_error("[NET] Missing TLS root certificate: %s" % TLS_ROOT_CERT_PATH)
        return TLSOptions.client()

    var cert := X509Certificate.new()
    var err := cert.load(TLS_ROOT_CERT_PATH)
    if err != OK:
        push_error("[NET] Failed to load TLS root certificate: %s (err=%s)" % [TLS_ROOT_CERT_PATH, err])
        return TLSOptions.client()

    return TLSOptions.client(cert)

func connect_to_server(_unused_url: String = "", reset_backoff: bool = true) -> void:
    _url = FORCED_WSS_URL
    if _url == "":
        return
    if is_open() or _connect_in_flight:
        return

    _allow_reconnect = true
    _disconnect_reason = ""
    if reset_backoff:
        _reset_reconnect_state()

    if _client_connection_lost:
        _connection_state = ConnectionState.RECOVERING
    else:
        _connection_state = ConnectionState.CONNECTING

    _connect_in_flight = true
    var tls_options := _build_tls_client_options()
    var err := _ws.connect_to_url(_url, tls_options)
    if err != OK:
        push_error("WebSocket connect error: %s" % err)
        _connect_in_flight = false
        _schedule_reconnect()
        return

func is_open() -> bool:
    return _ws.get_ready_state() == WebSocketPeer.STATE_OPEN

func close(code: int = 1000, reason: String = "") -> void:
    _allow_reconnect = false
    _disconnect_reason = String(reason).strip_edges()
    if _disconnect_reason == "":
        _disconnect_reason = DISCONNECT_REASON_CLOSE

    _client_connection_lost = false
    _connection_state = ConnectionState.IDLE

    _request_queue.clear()
    _pending_requests.clear()
    _pending_results.clear()
    _clear_activity_probe()
    _cancel_reconnect_timer()

    _is_authenticated = false
    _login_in_flight = false
    _connect_in_flight = false

    if is_open():
        _ws.close(code, _disconnect_reason)
    else:
        _was_open = false

func retry_now() -> void:
    if _url == "" or is_open():
        return
    _allow_reconnect = true
    _cancel_reconnect_timer()
    _reset_reconnect_state()
    _connect_in_flight = false
    connect_to_server(_url, true)

func set_login_credentials(username: String, pin: String) -> void:
    var user := username.strip_edges()
    var pin_value := pin.strip_edges()
    if user == "" or pin_value == "":
        return
    _auth_credentials = {"username": user, "pin": pin_value}

func clear_login_credentials() -> void:
    _auth_credentials.clear()
    _is_authenticated = false
    _login_in_flight = false

func has_login_credentials() -> bool:
    return String(_auth_credentials.get("username", "")) != "" and String(_auth_credentials.get("pin", "")) != ""

func _try_auto_login() -> void:
    if _is_authenticated or _login_in_flight or not has_login_credentials():
        return
    _login_in_flight = true
    request("login", _auth_credentials.duplicate(true), RequestPriority.CRITICAL)

func _reset_reconnect_state() -> void:
    _reconnect_delay_sec = RECONNECT_INITIAL_DELAY_SEC
    _reconnect_attempts = 0
    _cancel_reconnect_timer()

func _cancel_reconnect_timer() -> void:
    if _reconnect_timer:
        _reconnect_timer.queue_free()
        _reconnect_timer = null

func _schedule_reconnect() -> void:
    if not _allow_reconnect:
        return
    if _url == "":
        return
    if _reconnect_attempts >= _max_reconnect_attempts:
        _on_reconnect_exhausted()
        return

    _cancel_reconnect_timer()

    var delay_sec := _reconnect_delay_sec
    _reconnect_attempts += 1
    _reconnect_delay_sec = minf(_reconnect_delay_sec * RECONNECT_BACKOFF_MULTIPLIER, RECONNECT_MAX_DELAY_SEC)

    _reconnect_timer = Timer.new()
    add_child(_reconnect_timer)
    _reconnect_timer.one_shot = true
    _reconnect_timer.wait_time = delay_sec
    _reconnect_timer.timeout.connect(_on_reconnect_timeout)
    _reconnect_timer.start()

func _on_reconnect_exhausted() -> void:
    push_error("[NET] Max reconnect attempts reached (%d)" % _max_reconnect_attempts)
    if _connection_state == ConnectionState.RECOVERING and _client_connection_lost:
        reconnect_failed.emit()
    _connection_state = ConnectionState.IDLE
    disconnected.emit(1000, DISCONNECT_REASON_RECONNECT_MAX)

func _on_reconnect_timeout() -> void:
    if not _allow_reconnect:
        return
    _reconnect_timer = null
    connect_to_server(_url, false)

func _clear_activity_probe(keep_rid_for_late_response: bool = false) -> void:
    if keep_rid_for_late_response and _activity_probe_rid != "":
        _activity_probe_ignore_rid = _activity_probe_rid
    _activity_probe_in_flight = false
    _activity_probe_started_ms = 0
    _activity_probe_rid = ""

func _has_effective_pending_requests() -> bool:
    for rid in _pending_requests:
        if rid == _activity_probe_rid or rid == _activity_probe_ignore_rid:
            continue
        return true
    return false

func _send_activity_probe(now_ms: int) -> bool:
    _rid_counter += 1
    var rid := str(_rid_counter)
    if not _send_request_packet(rid, "ping", {}):
        return false
    _activity_probe_in_flight = true
    _activity_probe_started_ms = now_ms
    _activity_probe_rid = rid
    return true

func _check_pending_activity_timeout(now_ms: int) -> void:
    if not _allow_reconnect:
        return
    if not is_open():
        return
    if not _has_effective_pending_requests():
        _clear_activity_probe(true)
        return

    var silence_ms := now_ms - _last_rx_ms
    if silence_ms < PENDING_ACTIVITY_TIMEOUT_MS:
        _clear_activity_probe(true)
        return

    if _activity_probe_in_flight:
        var probe_wait_ms := now_ms - _activity_probe_started_ms
        if probe_wait_ms < PENDING_ACTIVITY_PROBE_TIMEOUT_MS:
            return
        _clear_activity_probe()
        _mark_client_connection_lost(PENDING_ACTIVITY_TIMEOUT_REASON)
        return

    if not _send_activity_probe(now_ms):
        _mark_client_connection_lost(PENDING_ACTIVITY_TIMEOUT_REASON)
        return

func _mark_client_connection_lost(reason: String) -> void:
    if _connection_state == ConnectionState.RECOVERING and _client_connection_lost:
        return

    _clear_activity_probe()
    _was_open = false
    _connect_in_flight = false
    _is_authenticated = false
    _login_in_flight = false
    _disconnect_reason = ""

    disconnected.emit(1006, reason)

    if not _client_connection_lost:
        _client_connection_lost = true
        connection_lost.emit()

    _connection_state = ConnectionState.RECOVERING
    _ws = WebSocketPeer.new()
    _schedule_reconnect()

func _process(_delta: float) -> void:
    _ws.poll()

    var st := _ws.get_ready_state()
    if st == WebSocketPeer.STATE_OPEN:
        if not _was_open:
            var was_recovering := _connection_state == ConnectionState.RECOVERING and _client_connection_lost
            _was_open = true
            _connect_in_flight = false
            _clear_activity_probe()
            _last_rx_ms = Time.get_ticks_msec()
            _reset_reconnect_state()
            _connection_state = ConnectionState.CONNECTED

            if has_login_credentials() and not _is_authenticated:
                _try_auto_login()
            else:
                _drain_queue()

            connected.emit()
            if was_recovering:
                _client_connection_lost = false
                connection_restored.emit()

    elif st == WebSocketPeer.STATE_CLOSED:
        if _was_open or _connect_in_flight:
            _handle_closed_state()
        return

    while _ws.get_available_packet_count() > 0:
        var pkt := _ws.get_packet().get_string_from_utf8()
        _handle_packet(pkt)

    _check_pending_activity_timeout(Time.get_ticks_msec())
    _check_request_timeouts()

func _handle_closed_state() -> void:
    _was_open = false
    _connect_in_flight = false
    _clear_activity_probe()
    _is_authenticated = false
    _login_in_flight = false

    var close_code := _ws.get_close_code()
    var close_reason := String(_ws.get_close_reason()).strip_edges()
    var reason := _resolve_disconnect_reason(close_reason)
    disconnected.emit(close_code, reason)

    var classification := _classify_disconnection(close_code, close_reason, reason, _allow_reconnect, _disconnect_reason)
    var cls := int(classification.get("class", DisconnectClass.CLIENT_LOST))

    match cls:
        DisconnectClass.VOLUNTARY:
            _connection_state = ConnectionState.IDLE
            _client_connection_lost = false
        DisconnectClass.SERVER_CLOSED_EXPLICIT:
            _connection_state = ConnectionState.IDLE
            _client_connection_lost = false
            _allow_reconnect = false
            server_closed.emit(
                String(classification.get("server_reason", "")),
                close_code,
                close_reason
            )
        _:
            if not _client_connection_lost:
                _client_connection_lost = true
                connection_lost.emit()
            _connection_state = ConnectionState.RECOVERING
            _schedule_reconnect()

    _disconnect_reason = ""

func _add_to_queue(
    type: String,
    data: Dictionary,
    priority: int,
    retries: int,
    timeout_sec: float
) -> String:
    _rid_counter += 1
    var rid := str(_rid_counter)

    if _request_queue.size() >= MAX_QUEUE_SIZE:
        push_warning("Request queue full, dropping: %s" % type)
        return ""

    var now_ms := Time.get_ticks_msec()
    var timeout_ms := int(timeout_sec * 1000.0)
    var item := {
        "rid": rid,
        "type": type,
        "data": data,
        "priority": priority,
        "retries": retries,
        "deadline_ms": now_ms + timeout_ms,
        "timeout_ms": timeout_ms,
        "added_at": now_ms
    }

    _request_queue.append(item)
    _pending_requests[rid] = item
    _request_queue.sort_custom(func(a, b): return a["priority"] > b["priority"])

    if is_open():
        _drain_queue()

    return rid

func _drain_queue() -> void:
    while not _request_queue.is_empty() and is_open():
        var item = _request_queue.pop_front()
        var sent := _send_request_packet(item["rid"], item["type"], item["data"])
        if not sent:
            _request_queue.insert(0, item)
            break

func _send_request_packet(rid: String, type: String, data: Dictionary) -> bool:
    var env := {
        "kind": "req",
        "type": type,
        "rid": rid,
        "data": data
    }

    var json_str := JSON.stringify(env)
    if json_str == "":
        push_error("JSON serialization failed for type: %s" % type)
        return false

    if not is_open():
        return false

    var err := _ws.send_text(json_str)
    if err != OK:
        push_error("WebSocket send failed for type: %s (error: %s)" % [type, err])
        return false

    return true

func _check_request_timeouts() -> void:
    var now := Time.get_ticks_msec()
    var expired_rids: Array[String] = []

    for rid in _pending_requests:
        var req = _pending_requests[rid] as Dictionary
        if now > req["deadline_ms"]:
            expired_rids.append(rid)

    for rid in expired_rids:
        var req = _pending_requests[rid] as Dictionary
        if req["retries"] < MAX_RETRIES:
            req["retries"] += 1
            var timeout_ms := int(req.get("timeout_ms", int(DEFAULT_TIMEOUT_SEC * 1000.0)))
            req["deadline_ms"] = Time.get_ticks_msec() + timeout_ms
            _request_queue.insert(0, req)
            _request_queue.sort_custom(func(a, b): return a["priority"] > b["priority"])
            _drain_queue()
        else:
            _pending_requests.erase(rid)
            response.emit(rid, req["type"], false, {}, {
                "message_code": LOCAL_ERROR_MESSAGE_CODE
            })

func _handle_packet(pkt: String) -> void:
    _last_rx_ms = Time.get_ticks_msec()
    if _activity_probe_in_flight:
        _clear_activity_probe(true)

    var json := JSON.new()
    var error := json.parse(pkt)
    if error != OK:
        push_error("JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
        return

    var parsed = json.data
    if typeof(parsed) != TYPE_DICTIONARY:
        return

    var env := parsed as Dictionary
    if env.has("v") and int(env.get("v")) != 1:
        return

    var kind := String(env.get("kind", ""))
    var type := String(env.get("type", ""))

    if kind == "evt":
        var data := env.get("data", {}) as Dictionary
        evt.emit(type, data)
        return

    if kind == "res":
        _handle_response(env)

func _handle_response(env: Dictionary) -> void:
    var rid := String(env.get("rid", ""))
    if rid != "" and rid == _activity_probe_ignore_rid:
        _activity_probe_ignore_rid = ""
        return

    var type := String(env.get("type", ""))
    var ok := bool(env.get("ok", false))
    var data := env.get("data", {}) as Dictionary
    var err := env.get("error", {}) as Dictionary

    if type == "login":
        _login_in_flight = false
        _is_authenticated = ok
        if ok:
            _drain_queue()
    elif type == "logout":
        clear_login_credentials()
        _allow_reconnect = false
        _disconnect_reason = DISCONNECT_REASON_LOGOUT

    _pending_results[rid] = {"rid": rid, "type": type, "ok": ok, "data": data, "error": err}
    _pending_requests.erase(rid)
    response.emit(rid, type, ok, data, err)

func request(
    type: String,
    data: Dictionary = {},
    priority: int = RequestPriority.NORMAL
) -> String:
    if type == "login":
        set_login_credentials(String(data.get("username", "")), String(data.get("pin", "")))
        _login_in_flight = true
    elif type == "logout":
        _allow_reconnect = false
        _disconnect_reason = DISCONNECT_REASON_LOGOUT
        clear_login_credentials()

    var rid := _add_to_queue(type, data, priority, 0, DEFAULT_TIMEOUT_SEC)
    if rid == "" and type == "login":
        _login_in_flight = false
    if rid == "" and type == "logout":
        close(1000, DISCONNECT_REASON_LOGOUT)
    return rid

func request_async(
    type: String,
    data: Dictionary = {},
    timeout_sec: float = DEFAULT_TIMEOUT_SEC,
    priority: int = RequestPriority.NORMAL
) -> Dictionary:
    var rid := request(type, data, priority)
    if rid == "":
        return {
            "rid": "",
            "type": type,
            "ok": false,
            "data": {},
            "error": {"message_code": LOCAL_ERROR_MESSAGE_CODE}
        }

    var deadline_msec := Time.get_ticks_msec() + int(timeout_sec * 1000.0)

    while Time.get_ticks_msec() < deadline_msec:
        if _pending_results.has(rid):
            var res := _pending_results[rid] as Dictionary
            _pending_results.erase(rid)
            return res
        await get_tree().process_frame

    return {
        "rid": rid,
        "type": type,
        "ok": false,
        "data": {},
        "error": {"message_code": LOCAL_ERROR_MESSAGE_CODE}
    }

func local_epoch_ms() -> int:
    return int(Time.get_unix_time_from_system() * 1000.0)

func server_now_ms() -> int:
    return local_epoch_ms() + server_clock_offset_ms

func sync_server_clock(server_epoch_ms: int) -> void:
    if server_epoch_ms > 0:
        server_clock_offset_ms = server_epoch_ms - local_epoch_ms()

func get_pending_request(rid: String) -> Dictionary:
    return _pending_requests.get(rid, {})

func _resolve_disconnect_reason(close_reason: String) -> String:
    var reason := _disconnect_reason
    if reason == "":
        reason = close_reason
    if reason == "":
        reason = "Connection lost"
    return reason

func _classify_disconnection(
    _close_code: int,
    close_reason: String,
    fallback_reason: String,
    allow_reconnect: bool,
    disconnect_reason: String
) -> Dictionary:
    var explicit_reason := close_reason if close_reason != "" else fallback_reason
    var normalized_disconnect_reason := String(disconnect_reason).strip_edges()

    if normalized_disconnect_reason == DISCONNECT_REASON_LOGOUT or normalized_disconnect_reason == DISCONNECT_REASON_CLOSE:
        return {"class": DisconnectClass.VOLUNTARY, "server_reason": ""}
    if not allow_reconnect and normalized_disconnect_reason != "":
        return {"class": DisconnectClass.VOLUNTARY, "server_reason": ""}

    if explicit_reason.begins_with(SERVER_CLOSE_REASON_PREFIX):
        var server_reason := explicit_reason.substr(SERVER_CLOSE_REASON_PREFIX.length())
        if server_reason == "":
            server_reason = explicit_reason
        return {"class": DisconnectClass.SERVER_CLOSED_EXPLICIT, "server_reason": server_reason}

    return {"class": DisconnectClass.CLIENT_LOST, "server_reason": ""}
