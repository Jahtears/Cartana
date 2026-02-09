# NetworkManager.gd v2.1 - Avec reconnexion automatique

extends Node

signal connected()
signal disconnected(code: int, reason: String)
signal response(rid: String, type: String, ok: bool, data: Dictionary, error: Dictionary)
signal evt(type: String, data: Dictionary)

# ============= CONSTANTS =============
const DEFAULT_TIMEOUT_SEC = 10.0
const MAX_RETRIES = 3
const RETRY_DELAY_MS = 500
const MAX_QUEUE_SIZE = 100
const HEARTBEAT_CHECK_MS = 5000

# ✅ NOUVEAU: Reconnexion automatique
const RECONNECT_INITIAL_DELAY_SEC = 3.0
const RECONNECT_MAX_DELAY_SEC = 30.0
const RECONNECT_BACKOFF_MULTIPLIER = 1.5

# ============= STATE =============
var _ws := WebSocketPeer.new()
var _url := ""
var _rid_counter: int = 0
var server_clock_offset_ms: int = 0
var _was_open: bool = false
var _last_pong_ms: int = 0

# Queue + Retry
var _request_queue: Array = []
var _pending_results: Dictionary = {}
var _pending_requests: Dictionary = {}

# Priorité
enum RequestPriority { LOW = 0, NORMAL = 5, HIGH = 8, CRITICAL = 10 }

# ✅ NOUVEAU: Reconnexion state
var _reconnect_timer: Timer = null
var _reconnect_delay_sec: float = RECONNECT_INITIAL_DELAY_SEC
var _reconnect_attempts: int = 0
var _max_reconnect_attempts: int = 10
var _auth_credentials: Dictionary = {}
var _is_authenticated: bool = false
var _login_in_flight: bool = false

# ============= LIFECYCLE =============

func _ready() -> void:
	pass

func connect_to_server(url: String = "ws://localhost:3000") -> void:
	_url = url
	_reset_reconnect_state()
	var err := _ws.connect_to_url(url)
	if err != OK:
		push_error("WebSocket connect error: %s" % err)
		_schedule_reconnect()
		return
	print("[NET] Connecting to %s" % url)

func is_open() -> bool:
	return _ws.get_ready_state() == WebSocketPeer.STATE_OPEN

func close(code: int = 1000, reason: String = "") -> void:
	_request_queue.clear()
	_pending_requests.clear()
	_cancel_reconnect_timer()
	_is_authenticated = false
	_login_in_flight = false
	if is_open():
		_ws.close(code, reason)

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

# ✅ NOUVEAU: Reset reconnect state
func _reset_reconnect_state() -> void:
	_reconnect_delay_sec = RECONNECT_INITIAL_DELAY_SEC
	_reconnect_attempts = 0
	_cancel_reconnect_timer()

# ✅ NOUVEAU: Annuler timer de reconnexion
func _cancel_reconnect_timer() -> void:
	if _reconnect_timer:
		_reconnect_timer.queue_free()
		_reconnect_timer = null

# ✅ NOUVEAU: Planifier reconnexion avec backoff exponentiel
func _schedule_reconnect() -> void:
	if _reconnect_attempts >= _max_reconnect_attempts:
		push_error("[NET] Max reconnect attempts reached (%d)" % _max_reconnect_attempts)
		disconnected.emit(1000, "Max reconnect attempts exceeded")
		return
	
	_cancel_reconnect_timer()
	
	# Backoff exponentiel: 3s → 4.5s → 6.7s → ... → 30s (max)
	_reconnect_delay_sec = minf(
		_reconnect_delay_sec * RECONNECT_BACKOFF_MULTIPLIER,
		RECONNECT_MAX_DELAY_SEC
	)
	_reconnect_attempts += 1
	
	print("[NET] Scheduling reconnect attempt %d in %.1fs" % [_reconnect_attempts, _reconnect_delay_sec])
	
	_reconnect_timer = Timer.new()
	add_child(_reconnect_timer)
	_reconnect_timer.one_shot = true
	_reconnect_timer.wait_time = _reconnect_delay_sec
	_reconnect_timer.timeout.connect(_on_reconnect_timeout)
	_reconnect_timer.start()

func _on_reconnect_timeout() -> void:
	print("[NET] Attempting reconnect #%d" % _reconnect_attempts)
	_reconnect_timer = null
	connect_to_server(_url)

# ============= PROCESS LOOP =============

func _process(_delta: float) -> void:
	_ws.poll()

	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			_last_pong_ms = Time.get_ticks_msec()
			_reset_reconnect_state()  # ✅ Reset backoff on success
			if has_login_credentials() and not _is_authenticated:
				_try_auto_login()
			else:
				_drain_queue()
			connected.emit()
			print("[NET] Connected to server")
	elif st == WebSocketPeer.STATE_CLOSED:
		if _was_open:
			_was_open = false
			_is_authenticated = false
			_login_in_flight = false
			disconnected.emit(0, "Connection lost")
			print("[NET] Connection closed, scheduling reconnect")
			_schedule_reconnect()  # ✅ Reconnect auto
		return

	# Recevoir les messages
	while _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet().get_string_from_utf8()
		_handle_packet(pkt)

	# Timeout des requêtes
	_check_request_timeouts()

# ============= QUEUE MANAGEMENT =============

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

	var deadline_ms = Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	var item = {
		"rid": rid,
		"type": type,
		"data": data,
		"priority": priority,
		"retries": retries,
		"deadline_ms": deadline_ms,
		"added_at": Time.get_ticks_msec()
	}

	_request_queue.append(item)
	_pending_requests[rid] = item

	# Trier par priorité (décroissant)
	_request_queue.sort_custom(func(a, b): return a["priority"] > b["priority"])

	if is_open():
		_drain_queue()

	return rid

func _drain_queue() -> void:
	while not _request_queue.is_empty() and is_open():
		var item = _request_queue.pop_front()
		var sent = _send_request_packet(item["rid"], item["type"], item["data"])
		
		if not sent:
			_request_queue.insert(0, item)
			break

func _send_request_packet(rid: String, type: String, data: Dictionary) -> bool:
	var env := {
		"v": 1,
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

# ============= TIMEOUT CHECK =============

func _check_request_timeouts() -> void:
	var now = Time.get_ticks_msec()
	var expired_rids: Array[String] = []

	for rid in _pending_requests:
		var req = _pending_requests[rid] as Dictionary
		if now > req["deadline_ms"]:
			expired_rids.append(rid)

	for rid in expired_rids:
		var req = _pending_requests[rid] as Dictionary
		if req["retries"] < MAX_RETRIES:
			# Retry
			req["retries"] += 1
			req["deadline_ms"] = Time.get_ticks_msec() + RETRY_DELAY_MS
			_request_queue.insert(0, req)
			_request_queue.sort_custom(func(a, b): return a["priority"] > b["priority"])
			_drain_queue()
		else:
			# Fail
			_pending_requests.erase(rid)
			response.emit(rid, req["type"], false, {}, {
				"code": "TIMEOUT",
				"message": "Request timeout after %d retries" % MAX_RETRIES
			})

# ============= PACKET HANDLING =============

func _handle_packet(pkt: String) -> void:
	var json = JSON.new()
	var error = json.parse(pkt)
	
	if error != OK:
		push_error("JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return
	
	var parsed = json.data
	
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var env := parsed as Dictionary
	if env.get("v") != 1:
		return

	var kind := String(env.get("kind", ""))
	var type := String(env.get("type", ""))

	if kind == "evt":
		var data := env.get("data", {}) as Dictionary
		evt.emit(type, data)
		return

	if kind == "res":
		var rid := String(env.get("rid", ""))
		var ok := bool(env.get("ok", false))
		var data := env.get("data", {}) as Dictionary
		var err := env.get("error", {}) as Dictionary

		if type == "login":
			_login_in_flight = false
			_is_authenticated = ok

		_pending_results[rid] = {"rid": rid, "type": type, "ok": ok, "data": data, "error": err}
		_pending_requests.erase(rid)

		response.emit(rid, type, ok, data, err)
		return

# ============= PUBLIC API =============

func request(
	type: String,
	data: Dictionary = {},
	priority: int = RequestPriority.NORMAL
) -> String:
	if type == "login":
		set_login_credentials(String(data.get("username", "")), String(data.get("pin", "")))
		_login_in_flight = true
	elif type == "logout":
		clear_login_credentials()

	return _add_to_queue(type, data, priority, 0, DEFAULT_TIMEOUT_SEC)

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
			"error": {"code": "CLIENT_ERROR", "message": "Queue full"}
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
		"error": {"code": "TIMEOUT", "message": "Request timeout"}
	}

# ============= CLOCK SYNC =============

func local_epoch_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

func server_now_ms() -> int:
	return local_epoch_ms() + server_clock_offset_ms

func sync_server_clock(server_epoch_ms: int) -> void:
	if server_epoch_ms > 0:
		server_clock_offset_ms = server_epoch_ms - local_epoch_ms()

# ============= DIAGNOSTICS =============

func get_queue_stats() -> Dictionary:
	return {
		"queue_size": _request_queue.size(),
		"pending_requests": _pending_requests.size(),
		"is_open": is_open(),
		"is_authenticated": _is_authenticated,
		"has_credentials": has_login_credentials(),
		"server_clock_offset_ms": server_clock_offset_ms,
		"reconnect_attempts": _reconnect_attempts,
		"reconnect_next_delay_sec": _reconnect_delay_sec,
	}

func get_pending_request(rid: String) -> Dictionary:
	return _pending_requests.get(rid, {})
