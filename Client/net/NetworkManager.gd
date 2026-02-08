# NetworkManager.gd v2.0 - Queue + Retry + Priorité + Heartbeat

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

# ============= LIFECYCLE =============

func _ready() -> void:
	pass

func connect_to_server(url: String = "ws://localhost:3000") -> void:
	_url = url
	var err := _ws.connect_to_url(url)
	if err != OK:
		push_error("WebSocket connect error: %s" % err)
		return

func is_open() -> bool:
	return _ws.get_ready_state() == WebSocketPeer.STATE_OPEN

func close(code: int = 1000, reason: String = "") -> void:
	_request_queue.clear()
	_pending_requests.clear()
	if is_open():
		_ws.close(code, reason)

# ============= PROCESS LOOP =============

func _process(_delta: float) -> void:
	_ws.poll()

	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			_last_pong_ms = Time.get_ticks_msec()
			_drain_queue()
			connected.emit()
	elif st == WebSocketPeer.STATE_CLOSED:
		if _was_open:
			_was_open = false
			disconnected.emit(0, "")
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
		"server_clock_offset_ms": server_clock_offset_ms
	}

func get_pending_request(rid: String) -> Dictionary:
	return _pending_requests.get(rid, {})
