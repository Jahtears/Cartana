# Game.gd V2.0 -  système d'événements et slots

extends Control 

# ============= SCENES =============
var slot_scene: PackedScene = preload("res://Client/Scenes/Slot.tscn")
var card_scene: PackedScene = preload("res://Client/Scenes/Carte.tscn")

# ============= PROTOCOLS & HELPERS =============
const Protocol = preload("res://Client/net/Protocol.gd")
const GameMessage = preload("res://Client/game/messages/GameMessage.gd")
const SlotIdHelper = preload("res://Client/game/helpers/slot_id.gd")
const TableSyncHelper = preload("res://Client/game/helpers/table_sync.gd")
const CardSyncHelper = preload("res://Client/game/helpers/card_sync.gd")
const TimebarUtil = preload("res://Client/game/helpers/timebar.gd")
const POPUP_PREFIX := "MSG_POPUP_"

const FLOW_INVITE_REQUEST_FALLBACK := "invite_request"

const REQ_JOIN_GAME := "join_game"
const REQ_SPECTATE_GAME := "spectate_game"
const REQ_INVITE_RESPONSE := "invite_response"
const REQ_ACK_GAME_END := "ack_game_end"
const REQ_LEAVE_GAME := "leave_game"

const ACTION_GAME_END_LEAVE := "game_end_leave"
const ACTION_GAME_END_STAY := "game_end_stay"
const ACTION_QUIT_CANCEL := "quit_cancel"
const ACTION_QUIT_CONFIRM := "quit_confirm"
const ACTION_PAUSE_WAIT := "pause_wait"
const ACTION_PAUSE_LEAVE := "pause_leave"

const LABEL_BACK_TO_LOBBY := "Retour lobby"
const LABEL_STAY := "Rester"
const LABEL_CANCEL := "Annuler"
const LABEL_QUIT := "Quitter"
const LABEL_WAIT := "Attendre"

# ============= LAYOUT CONSTANTS =============
const MAIN_COUNT := 1
const BANC_COUNT := 4
const MIN_SLOT_SPACING := 64.0
const MAX_SLOT_SPACING := 120.0
const SLOT_WIDTH := 80.0
const SIDE_MARGIN := 100.0
const PLAYER_TOP_Y_RATIO := 0.18
const PLAYER_BOTTOM_Y_RATIO := 0.82
const TABLE_Y_RATIO := 0.5
const PIOCHE_RIGHT_MARGIN := 80.0
const START_POS := Vector2.ZERO

# ============= TIMEBAR COLORS =============
static var TIMEBAR_GREEN: Color = Color.from_hsv(0.333, 0.85, 0.95, 1.0)
static var TIMEBAR_YELLOW: Color = Color.from_hsv(0.166, 0.85, 0.95, 1.0)
static var TIMEBAR_ORANGE: Color = Color.from_hsv(0.083, 0.85, 0.95, 1.0)
static var TIMEBAR_RED: Color = Color.from_hsv(0.000, 0.85, 0.95, 1.0)
const TIMEBAR_SPEC: Color = Color(0.85, 0.85, 0.85)

# ============= STATE =============
var slots_ready: bool = false
var slots_by_id: Dictionary = {}
var pending_events: Array[Dictionary] = []
var cards: Dictionary = {}
var allowed_table_slots: Dictionary = {}

# ============= UI STATE =============
var _is_changing_scene := false
var _game_end_prompted := false
var _leave_sent := false
var _disconnect_prompt_seq := 0
var _opponent_disconnected := false

# ============= LAYOUT STATE =============
var _slot_spacing: float = 100.0
var _table_spacing: int = 100

# ============= NODES =============
@onready var time_bar: ProgressBar = $TimeBar
@onready var player1_root: Node2D = $Player1
@onready var player2_root: Node2D = $Player2
@onready var player1_deck: Node2D = $Player1/Deck
@onready var player1_main: Node2D = $Player1/Main
@onready var player1_banc: Node2D = $Player1/Banc
@onready var player2_deck: Node2D = $Player2/Deck
@onready var player2_main: Node2D = $Player2/Main
@onready var player2_banc: Node2D = $Player2/Banc
@onready var pioche_root: Node2D = $Pioche
@onready var table_root: Node2D = $Table
@onready var game_message_label: RichTextLabel = $VBoxContainer/CenterContainer/GameMessage
@onready var game_message_timer: Timer = $VBoxContainer/Timer

# ============= CARD CONTEXT =============
var _card_ctx: Dictionary = {}

# ============= TIMEBAR STATE =============
var _timebar_state: Dictionary = {
	"turn_current": "",
	"turn_ends_at_ms": 0,
	"turn_duration_ms": 0,
	"turn_paused": false,
	"turn_remaining_ms": 0,
	"timebar_mode": -1,
	"timebar_fill_sb": null,
	"timebar_last_color": Color(-1, -1, -1, -1),
}

var _timebar_colors: Dictionary = {
	"green": TIMEBAR_GREEN,
	"yellow": TIMEBAR_YELLOW,
	"orange": TIMEBAR_ORANGE,
	"red": TIMEBAR_RED,
	"spec": TIMEBAR_SPEC,
}

# ============= LIFECYCLE =============

func _ready() -> void:
	_connect_layout_signals()
	_relayout_board()
	_setup_player($Player1, 1)
	_setup_player($Player2, 2)
	_setup_Pioche($Pioche)
	
	_card_ctx = {
		"cards": cards,
		"card_scene": card_scene,
		"slots_by_id": slots_by_id,
		"root": self,
	}

	if not NetworkManager.evt.is_connected(_on_evt):
		NetworkManager.evt.connect(_on_evt)
	if not NetworkManager.response.is_connected(_on_response):
		NetworkManager.response.connect(_on_response)
	if not NetworkManager.disconnected.is_connected(_on_network_disconnected):
		NetworkManager.disconnected.connect(_on_network_disconnected)
	if not PopupUi.action_selected.is_connected(_on_popup_action):
		PopupUi.action_selected.connect(_on_popup_action)
	PopupUi.hide()

	# Ready pour la scène
	if String(Global.current_game_id) != "":
		_request_game_sync()

	await get_tree().process_frame
	slots_ready = true
	TimebarUtil.update_timebar(_timebar_state, time_bar, Callable(NetworkManager, "server_now_ms"), _timebar_colors)
	
	# Replay events avant que les slots soient prêts
	for ev in pending_events:
		_on_evt(String(ev.get("type", "")), ev.get("data", {}) as Dictionary)
	pending_events.clear()

# ============= EVENTS (PUSH SERVEUR) =============

func _on_evt(type: String, data: Dictionary) -> void:
	match type:
		"start_game":
			_handle_start_game(data)
		"table_sync":
			_handle_table_sync(data)
		"slot_state":
			_handle_slot_state(data)
		"state_snapshot":
			_handle_state_snapshot(data)
		"show_game_message":
			_show_game_feedback(data)
		"game_end":
			_handle_game_end(data)
		"turn_update":
			_set_turn_timer(data)
		"opponent_disconnected":
			_handle_opponent_disconnected(data)
		"opponent_rejoined":
			_handle_opponent_rejoined(data)
		"invite_request":
			_handle_invite_request(data)
		"invite_response":
			_handle_invite_response(data)
		"invite_cancelled":
			_handle_invite_cancelled(data)


# ============= HANDLERS =============

func _handle_invite_request(data: Dictionary) -> void:
	var from_user := String(data.get("from", ""))
	if from_user != "":
		PopupUi.show_invite_request(from_user, {
			"flow": Protocol.popup_flow("INVITE_REQUEST", FLOW_INVITE_REQUEST_FALLBACK),
			"from": from_user
		})

func _handle_invite_response(data: Dictionary) -> void:
	var ui := Protocol.normalize_invite_response_ui(data)
	if String(ui.get("text", "")) != "":
		PopupUi.show_ui_message(ui)

func _handle_invite_cancelled(data: Dictionary) -> void:
	var ui := Protocol.invite_cancelled_ui(data)
	if String(ui.get("text", "")).strip_edges() == "":
		return
	PopupUi.show_ui_message(ui)

func _handle_start_game(data: Dictionary) -> void:
	Global.current_game_id = String(data.get("game_id", ""))
	Global.players_in_game = data.get("players", [])
	Global.is_spectator = bool(data.get("spectator", false))

	Global.result.clear()

	_reset_board_state()
	slots_ready = true
	pending_events.clear()
	_is_changing_scene = false
	_game_end_prompted = false
	_leave_sent = false
	_opponent_disconnected = false
	_disconnect_prompt_seq += 1
	PopupUi.hide()

	if Global.current_game_id != "":
		_request_game_sync()

func _handle_table_sync(data: Dictionary) -> void:
	if slots_ready:
		TableSyncHelper.sync_table_slots(table_root, slot_scene, slots_by_id, allowed_table_slots, data.get("slots", []), _table_spacing, START_POS)
	else:
		pending_events.append({"type": "table_sync", "data": data})

func _handle_slot_state(data: Dictionary) -> void:
	if slots_ready:
		_on_slot_state(data)
	else:
		pending_events.append({"type": "slot_state", "data": data})

func _handle_state_snapshot(data: Dictionary) -> void:
	if slots_ready:
		_apply_state_snapshot(data)
	else:
		pending_events.append({"type": "state_snapshot", "data": data})

func _handle_game_end(data: Dictionary) -> void:
	Global.result = data.duplicate()
	var merged := data.duplicate(true)
	merged["game_id"] = String(merged.get("game_id", String(Global.current_game_id)))
	_on_game_end(merged)

func _handle_opponent_disconnected(data: Dictionary) -> void:
	var who := String(data.get("username", ""))
	_opponent_disconnected = true
	PopupUi.show_ui_message({
		"message_code": Protocol.MSG_POPUP_OPPONENT_DISCONNECTED,
		"message_params": { "name": who },
	})
	_schedule_disconnect_choice(who)

func _handle_opponent_rejoined(data: Dictionary) -> void:
	var who := String(data.get("username", ""))
	_opponent_disconnected = false
	_disconnect_prompt_seq += 1
	PopupUi.hide()
	PopupUi.show_ui_message({
		"message_code": Protocol.MSG_POPUP_OPPONENT_REJOINED,
		"message_params": { "name": who },
	})

# ============= RESPONSES =============

func _on_response(_rid: String, type: String, ok: bool, _data: Dictionary, error: Dictionary) -> void:
	if type == "login":
		if ok and String(Global.current_game_id) != "":
			_request_game_sync()
		return

	if type != "move_request":
		return

	# Reset move pending flag
	var card_id = _data.get("card_id", "")
	if card_id != "":
		var card = cards.get(card_id)
		if card and card.has_method("_reset_move_pending"):
			card._reset_move_pending()

	if ok:
		_show_game_feedback({
			"message_code": GameMessage.MSG_INLINE_MOVE_OK,
		})
	else:
		var ui := Protocol.normalize_error_message(error, GameMessage.MSG_INLINE_MOVE_DENIED)
		var details := error.get("details", {}) as Dictionary
		_show_game_feedback(ui)

		if details.has("card_id") and details.has("from_slot_id"):
			_on_invalid_move({
				"card_id": String(details.get("card_id", "")),
				"from_slot_id": String(details.get("from_slot_id", ""))
			})

func _on_network_disconnected(_code: int, reason: String) -> void:
	if String(reason).strip_edges() == NetworkManager.DISCONNECT_REASON_LOGOUT:
		return
	PopupUi.show_ui_message({
		"message_code": Protocol.MSG_POPUP_AUTH_CONNECTION_ERROR,
	})

func _request_game_sync() -> void:
	var game_id := String(Global.current_game_id)
	if game_id == "":
		return

	if bool(Global.is_spectator):
		NetworkManager.request(REQ_SPECTATE_GAME, {"game_id": game_id})
	else:
		NetworkManager.request(REQ_JOIN_GAME, {"game_id": game_id})

# ============= SNAPSHOT =============

func _apply_state_snapshot(data: Dictionary) -> void:
	for s in slots_by_id.values():
		if s and s.has_method("clear_slot"):
			s.clear_slot()

	TableSyncHelper.sync_table_slots(table_root, slot_scene, slots_by_id, allowed_table_slots, data.get("table", []), _table_spacing, START_POS)

	var slots_dict: Dictionary = data.get("slots", {})
	for k in slots_dict.keys():
		var slot_id := SlotIdHelper.normalize_slot_id(String(k))
		var slot := _find_slot_by_id(slot_id)

		if slot == null and SlotIdHelper.is_table_slot_id(slot_id):
			slot = _find_slot_by_id(slot_id)

		var arr: Array = slots_dict.get(k, [])
		
		# ✅ CORRECTION #3: Ajouter index d'ordre du serveur à chaque carte
		for i in range(arr.size()):
			var payload = arr[i]
			if payload is Dictionary:
				payload["_array_order"] = i  # Index du serveur
				CardSyncHelper.apply_card_update(_card_ctx, payload)

	# ✅ CORRECTION: Timebar depuis snapshot (hors boucle)
	var turn_val = data.get("turn", null)
	if turn_val is Dictionary:
		_set_turn_timer(turn_val as Dictionary)
	else:
		_set_turn_timer({})

	# ✅ CORRECTION: result via snapshot
	var result_val = data.get("result", null)
	if result_val is Dictionary and (result_val as Dictionary).size() > 0:
		var e := result_val as Dictionary
		var merged := {"game_id": String(Global.current_game_id)}
		for kk in e.keys():
			merged[kk] = e[kk]
		_on_game_end(merged)


# ============= GAME END =============

func _on_game_end(data: Dictionary) -> void:
	if _game_end_prompted:
		return
	_game_end_prompted = true
	var popup_msg := Protocol.game_end_popup_message(data, String(Global.username), bool(Global.is_spectator))
	var msg := String(popup_msg.get("text", ""))

	PopupUi.show_confirm(
		msg,
		LABEL_BACK_TO_LOBBY,
		LABEL_STAY,
		{
			"yes_action_id": ACTION_GAME_END_LEAVE,
			"no_action_id": ACTION_GAME_END_STAY,
			"game_id": String(Global.current_game_id),
		}
	)

func _ack_end_and_go_lobby() -> void:
	var gid := String(Global.current_game_id)
	if gid != "":
		await NetworkManager.request_async(REQ_ACK_GAME_END, {"game_id": gid}, 6.0)

	Global.current_game_id = ""
	Global.players_in_game = []
	Global.is_spectator = false
	Global.result = {}

	await _go_to_lobby_safe()

# ============= SLOT STATE =============

func _on_slot_state(data: Dictionary) -> void:
	var slot_id := SlotIdHelper.normalize_slot_id(String(data.get("slot_id", "")))
	if slot_id == "":
		return

	var slot := _find_slot_by_id(slot_id)

	if slot == null and SlotIdHelper.is_table_slot_id(slot_id):
		if not allowed_table_slots.has(slot_id):
			return
		slot = _find_slot_by_id(slot_id)

	if slot and slot.has_method("clear_slot"):
		slot.clear_slot()

	var arr: Array = data.get("cards", [])
	
	# ✅ CORRECTION #3: Ajouter index à chaque carte
	for i in range(arr.size()):
		var payload = arr[i]
		if payload is Dictionary:
			payload["_array_order"] = i  # Index du serveur
			CardSyncHelper.apply_card_update(_card_ctx, payload)


# ============= INVALID MOVE =============

func _on_invalid_move(data: Dictionary) -> void:
	var card_id: String = String(data.get("card_id", ""))
	var from_slot_id: String = SlotIdHelper.normalize_slot_id(String(data.get("from_slot_id", "")))
	if card_id == "" or from_slot_id == "":
		return

	var card = CardSyncHelper.get_or_create_card(_card_ctx, card_id)
	var slot = _find_slot_by_id(from_slot_id)
	if slot:
		slot.snap_card(card, true)
		card.set_meta("last_slot_id", from_slot_id)

# ============= RESET =============

func _reset_board_state() -> void:
	for s in slots_by_id.values():
		if s and s.has_method("clear_slot"):
			s.clear_slot()

	TableSyncHelper.sync_table_slots(table_root, slot_scene, slots_by_id, allowed_table_slots, ["0:TABLE:1"], _table_spacing, START_POS)

	for k in cards.keys():
		var c = cards[k]
		if is_instance_valid(c):
			c.queue_free()
	cards.clear()

	pending_events.clear()
	slots_ready = true
	allowed_table_slots.clear()

# ============= SETUP SLOTS =============

func _setup_player(player: Node, id: int) -> void:
	var deck = player.get_node("Deck")
	var main = player.get_node("Main")
	var banc = player.get_node("Banc")
	_create_slot(deck, "%d:DECK:1" % id, START_POS)
	for i in range(MAIN_COUNT):
		_create_slot(main, "%d:HAND:%d" % [id, i + 1], START_POS + Vector2(i * _slot_spacing, 0))
	for i in range(BANC_COUNT):
		_create_slot(banc, "%d:BENCH:%d" % [id, i + 1], START_POS + Vector2(i * _slot_spacing, 0))

func _setup_Pioche(pioche: Node) -> void:
	_create_slot(pioche, "0:PILE:1", START_POS)

func _slot_node_name(slot_id: String) -> String:
	return SlotIdHelper.slot_node_name(slot_id)

func _find_child_slot_by_id(parent: Node, slot_id: String) -> Node:
	for child in parent.get_children():
		if child != null and child.has_method("get_slot_id"):
			var cid := String(child.call("get_slot_id"))
			if cid == slot_id:
				return child
	return null

func _create_slot(parent: Node, slot_name: String, pos: Vector2) -> void:
	var existing := _find_child_slot_by_id(parent, slot_name)
	if existing != null:
		existing.name = _slot_node_name(slot_name)
		existing.slot_id = slot_name
		slots_by_id[slot_name] = existing
		return

	var node_name := _slot_node_name(slot_name)
	if parent.has_node(node_name):
		var existing2 := parent.get_node(node_name)
		existing2.slot_id = slot_name
		slots_by_id[slot_name] = existing2
		return
	var slot := slot_scene.instantiate()
	slot.name = _slot_node_name(slot_name)
	slot.slot_id = slot_name
	slot.position = pos
	parent.add_child(slot)
	slots_by_id[slot_name] = slot

# ============= FIND SLOT =============

func _find_slot_by_id(slot_id: String) -> Node:
	return slots_by_id.get(slot_id, null)

# ============= LAYOUT =============

func _connect_layout_signals() -> void:
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)

func _on_viewport_size_changed() -> void:
	_relayout_board()

func _relayout_board() -> void:
	var view_size := get_viewport_rect().size
	if view_size == Vector2.ZERO:
		return

	var vw := view_size.x
	var vh := view_size.y
	_slot_spacing = clampf(vw * 0.085, MIN_SLOT_SPACING, MAX_SLOT_SPACING)
	var edge_left_center := SIDE_MARGIN + SLOT_WIDTH * 0.5
	var edge_right_center := vw - SIDE_MARGIN - SLOT_WIDTH * 0.5
	var bench_steps: int = maxi(BANC_COUNT - 1, 1)
	var center_keepout := SLOT_WIDTH * 1.2
	var table_center_x: float = vw * 0.5
	var max_spacing_from_edges: float = (edge_right_center - (table_center_x + center_keepout)) / float(bench_steps)
	_slot_spacing = minf(_slot_spacing, maxf(56.0, max_spacing_from_edges))
	_table_spacing = int(round(_slot_spacing))

	var bench_span := float(BANC_COUNT - 1) * _slot_spacing
	var p1_deck_center := edge_left_center
	var p1_bench_start := edge_right_center - bench_span
	var p1_main_center: float = (p1_deck_center + table_center_x) * 0.6

	var p2_bench_start := edge_left_center
	var p2_deck_center := edge_right_center
	var p2_main_center: float = (p2_deck_center + table_center_x) * 0.45

	player1_root.position = Vector2(0, clampf(vh * PLAYER_BOTTOM_Y_RATIO, vh * 0.65, vh - 80.0))
	player2_root.position = Vector2(0, clampf(vh * PLAYER_TOP_Y_RATIO, 80.0, vh * 0.35))
	player1_deck.position = Vector2(p1_deck_center, 0)
	player1_main.position = Vector2(p1_main_center, 0)
	player1_banc.position = Vector2(p1_bench_start, 0)

	player2_banc.position = Vector2(p2_bench_start, 0)
	player2_main.position = Vector2(p2_main_center, 0)
	player2_deck.position = Vector2(p2_deck_center, 0)

	table_root.position = Vector2(table_center_x, vh * TABLE_Y_RATIO)
	pioche_root.position = Vector2(maxf(vw - PIOCHE_RIGHT_MARGIN, edge_right_center), vh * TABLE_Y_RATIO)

	_update_slot_rows()
	TableSyncHelper.update_table_positions(table_root, _table_spacing, START_POS)

func _update_slot_rows() -> void:
	_update_row_positions(1, "HAND", MAIN_COUNT)
	_update_row_positions(1, "BENCH", BANC_COUNT)
	_update_row_positions(2, "HAND", MAIN_COUNT)
	_update_row_positions(2, "BENCH", BANC_COUNT)

func _update_row_positions(player_id: int, slot_type: String, count: int) -> void:
	for i in range(count):
		var slot_id := "%d:%s:%d" % [player_id, slot_type, i + 1]
		var slot := _find_slot_by_id(slot_id)
		if slot != null:
			slot.position = START_POS + Vector2(i * _slot_spacing, 0)

# ============= UI MESSAGES =============

func _show_game_feedback(ui_message: Dictionary) -> void:
	var normalized := Protocol.normalize_game_message(ui_message)
	var message_code := String(normalized.get("message_code", "")).strip_edges()
	if GameMessage.normalize_inline_message(normalized).is_empty():
		if message_code.begins_with(POPUP_PREFIX):
			PopupUi.show_ui_message(normalized)
		return
	GameMessage.show_inline_message(normalized, game_message_label, game_message_timer)

func _on_timer_timeout() -> void:
	game_message_label.visible = false

# ============= TIMEBAR =============

func _process(_delta: float) -> void:
	if time_bar.visible:
		TimebarUtil.update_timebar(_timebar_state, time_bar, Callable(NetworkManager, "server_now_ms"), _timebar_colors)

func _set_turn_timer(turn: Dictionary) -> void:
	TimebarUtil.set_turn_timer(_timebar_state, turn, Callable(NetworkManager, "sync_server_clock"))
	TimebarUtil.update_timebar_mode(_timebar_state, bool(Global.is_spectator), String(Global.username))
	TimebarUtil.update_timebar(_timebar_state, time_bar, Callable(NetworkManager, "server_now_ms"), _timebar_colors)

# ============= QUITTER =============

func _on_quitter_pressed() -> void:
	PopupUi.show_confirm(
		Protocol.popup_text(Protocol.MSG_POPUP_QUIT_CONFIRM),
		LABEL_CANCEL,
		LABEL_QUIT,
		{
			"yes_action_id": ACTION_QUIT_CANCEL,
			"no_action_id": ACTION_QUIT_CONFIRM,
		}
	)

func _show_pause_choice(msg: String) -> void:
	PopupUi.show_confirm(
		msg,
		LABEL_WAIT,
		LABEL_BACK_TO_LOBBY,
		{
			"yes_action_id": ACTION_PAUSE_WAIT,
			"no_action_id": ACTION_PAUSE_LEAVE,
		}
	)

func _schedule_disconnect_choice(who: String) -> void:
	_disconnect_prompt_seq += 1
	var seq := _disconnect_prompt_seq
	var timer := get_tree().create_timer(5.0)
	timer.timeout.connect(func() -> void:
		if seq != _disconnect_prompt_seq:
			return
		if not _opponent_disconnected:
			return
		_show_pause_choice(
			Protocol.popup_text(
				Protocol.MSG_POPUP_OPPONENT_DISCONNECTED_CHOICE,
				{ "name": who }
			)
		)
	)

func _on_popup_action(action_id: String, payload: Dictionary) -> void:
	var invite_req := Protocol.invite_action_request(action_id, payload)
	if not invite_req.is_empty():
		NetworkManager.request(REQ_INVITE_RESPONSE, invite_req)
		return

	match action_id:
		ACTION_QUIT_CONFIRM, ACTION_PAUSE_LEAVE:
			await _leave_current_and_go_lobby()
		ACTION_GAME_END_LEAVE:
			await _ack_end_and_go_lobby()
		_:
			pass

func _leave_current_and_go_lobby() -> void:
	if _leave_sent:
		return
	_leave_sent = true

	var gid := String(Global.current_game_id)
	if gid != "":
		var has_result := (Global.result is Dictionary and (Global.result as Dictionary).size() > 0)

		if has_result:
			await NetworkManager.request_async(REQ_ACK_GAME_END, {"game_id": gid}, 4.0)
		else:
			if Global.is_spectator:
				await NetworkManager.request_async(REQ_ACK_GAME_END, {"game_id": gid}, 4.0)
			else:
				NetworkManager.request(REQ_LEAVE_GAME, {"game_id": gid})

	Global.reset_game_state()
	await _go_to_lobby_safe()

func _go_to_lobby_safe() -> void:
	if _is_changing_scene:
		return
	_is_changing_scene = true

	get_viewport().gui_disable_input = true
	await get_tree().process_frame
	get_viewport().gui_disable_input = false

	get_tree().change_scene_to_file("res://Client/Scenes/Lobby.tscn")

func _exit_tree() -> void:
	if String(Global.current_game_id) != "":
		NetworkManager.request(REQ_ACK_GAME_END, {"game_id": String(Global.current_game_id)})

	if NetworkManager.evt.is_connected(_on_evt):
		NetworkManager.evt.disconnect(_on_evt)
	if NetworkManager.response.is_connected(_on_response):
		NetworkManager.response.disconnect(_on_response)
	if NetworkManager.disconnected.is_connected(_on_network_disconnected):
		NetworkManager.disconnected.disconnect(_on_network_disconnected)
	if PopupUi.action_selected.is_connected(_on_popup_action):
		PopupUi.action_selected.disconnect(_on_popup_action)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if String(Global.current_game_id) != "":
			NetworkManager.request(REQ_ACK_GAME_END, {"game_id": String(Global.current_game_id)})
