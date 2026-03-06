# Game.gd - Main game controller (layout + coordination)

extends Control

# ============= SCENES =============
var slot_scene: PackedScene = preload("res://Client/Scenes/Slot.tscn")
var card_scene: PackedScene = preload("res://Client/Scenes/Carte.tscn")

# ============= CONFIG & HELPERS =============
const Protocol = preload("res://Client/net/Protocol.gd")
# ============= CONSTANTS =============
const REMATCH_CONTEXT := "rematch"
const ACK_INTENT_REMATCH := "rematch"

const REQ_JOIN_GAME := "join_game"
const REQ_SPECTATE_GAME := "spectate_game"
const REQ_ACK_GAME_END := "ack_game_end"
const REQ_LEAVE_GAME := "leave_game"
const REQ_INVITE := "invite"
const REQ_INVITE_RESPONSE := "invite_response"

const ACTION_GAME_END_LEAVE := "game_end_leave"
const ACTION_GAME_END_REMATCH := "game_end_rematch"
const ACTION_REMATCH_DECLINED_LEAVE := "rematch_declined_leave"
const ACTION_QUIT_CANCEL := "quit_cancel"
const ACTION_QUIT_CONFIRM := "quit_confirm"
const ACTION_PAUSE_WAIT := "pause_wait"
const ACTION_PAUSE_LEAVE := "pause_leave"
const ACTION_NETWORK_RETRY := "network_retry"

const UI_GAME_QUIT_BUTTON_KEY := "UI_GAME_QUIT_BUTTON"

# ============= STATE =============
var slots_ready: bool = false
var slots_by_id: Dictionary = {}
var pending_events: Array[Dictionary] = []
var cards: Dictionary = {}
var allowed_table_slots: Dictionary = {}

# ============= UI STATE =====
var _is_changing_scene := false
var _game_end_prompted := false
var _leave_sent := false
var _disconnect_prompt_seq := 0
var _opponent_disconnected := false
var _network_disconnected := false
var _message_tween: Tween = null
var _deck_count_state: Dictionary = DeckCountUtil.create_state()

# ============= LAYOUT STATE =============
var _slot_spacing: float = GameLayoutConfig.DEFAULT_SLOT_SPACING
var _table_spacing: int = GameLayoutConfig.TABLE_SPACING
var _positions_cache: Dictionary = {}

# ============= LAYOUT CONSTANTS =============
var START_POS: Vector2 = GameLayoutConfig.START_POS

# ============= NODES =============
@onready var player1_root: Node2D = $Board/Player1
@onready var player2_root: Node2D = $Board/Player2
@onready var p1_main_anchor: Node2D = $Board/Player1/Main
@onready var p1_banc_anchor: Node2D = $Board/Player1/Banc
@onready var pioche_root: Node2D = $Board/Pioche
@onready var table_root: Node2D = $Board/Table
@onready var quitter_button: Button = $Quitter

# ============= CARD CONTEXT =============
var _card_ctx: Dictionary = {}

# ============= TIMEBAR STATE =============
var _timebar_state: Dictionary = TimebarUtil.create_state()
var _game_message_state: Dictionary = GameMessage.create_ui_state()

# ============= LIFECYCLE =============

func _ready() -> void:
	_connect_layout_signals()
	_init_layout()
	
	_card_ctx = {
		"cards": cards,
		"card_scene": card_scene,
		"slots_by_id": slots_by_id,
		"root": self,
	}

	# ===== CONNECTER LES SIGNAUX RÉSEAU =====
	if not NetworkManager.evt.is_connected(_on_evt):
		NetworkManager.evt.connect(_on_evt)
	if not NetworkManager.response.is_connected(_on_response):
		NetworkManager.response.connect(_on_response)
	if not NetworkManager.connection_lost.is_connected(_on_connection_lost):
		NetworkManager.connection_lost.connect(_on_connection_lost)
	if not NetworkManager.connection_restored.is_connected(_on_connection_restored):
		NetworkManager.connection_restored.connect(_on_connection_restored)
	if not NetworkManager.reconnect_failed.is_connected(_on_reconnect_failed):
		NetworkManager.reconnect_failed.connect(_on_reconnect_failed)
	if not NetworkManager.server_closed.is_connected(_on_server_closed):
		NetworkManager.server_closed.connect(_on_server_closed)
	if not PopupUi.action_selected.is_connected(_on_popup_action):
		PopupUi.action_selected.connect(_on_popup_action)
	if not LanguageManager.language_changed.is_connected(_on_language_changed):
		LanguageManager.language_changed.connect(_on_language_changed)
	
	if not quitter_button.pressed.is_connected(_on_quitter_pressed):
		quitter_button.pressed.connect(_on_quitter_pressed)
	
	PopupUi.hide_and_reset()
	_apply_language_to_game_ui()

	if String(Global.current_game_id) != "":
		_request_game_sync()

	await get_tree().process_frame
	slots_ready = true
	TimebarUtil.update_timebar(_timebar_state, Callable(NetworkManager, "server_now_ms"))

	for event in pending_events:
		_on_evt(event.get("type", ""), event.get("data", {}))
	pending_events.clear()

# ============= LAYOUT INITIALIZATION (SIMPLIFIÉ) =============

func _init_layout() -> void:
	"""Initialise layout + slots fixes (sans reflow rows)"""
	_reflow_layout(true, false, false)
	_init_ui()

func _compute_layout_context() -> Dictionary:
	var view_size := get_viewport().get_visible_rect().size
	var vw := view_size.x
	var vh := view_size.y
	var slot_spacing := GameLayoutConfig.DEFAULT_SLOT_SPACING

	if GameLayoutConfig.BANC_COUNT > 1:
		var available_width := vw - GameLayoutConfig.SIDE_MARGIN * 2
		slot_spacing = clampf(
			available_width / float(GameLayoutConfig.BANC_COUNT + 1),
			GameLayoutConfig.MIN_SLOT_SPACING,
			GameLayoutConfig.MAX_SLOT_SPACING
		)

	return {
		"vw": vw,
		"vh": vh,
		"center_x": vw * 0.5,
		"left_x": GameLayoutConfig.SIDE_MARGIN,
		"right_x": vw - GameLayoutConfig.SIDE_MARGIN,
		"slot_spacing": slot_spacing,
	}

func _apply_layout_context(ctx: Dictionary) -> void:
	_positions_cache = ctx
	_slot_spacing = float(ctx.get("slot_spacing", GameLayoutConfig.DEFAULT_SLOT_SPACING))
	_apply_positions(_positions_cache)

func _apply_players_layout(create_slots: bool) -> void:
	_setup_player(player1_root, 1, create_slots)
	_setup_player(player2_root, 2, create_slots)

func _ensure_static_slots_once() -> void:
	_create_slot(pioche_root, "0:PILE:1", START_POS)

func _reflow_layout(create_slots: bool, apply_linked_ui: bool, refresh_slot_rows: bool) -> void:
	var ctx := _compute_layout_context()
	_apply_layout_context(ctx)
	_apply_players_layout(create_slots)

	if create_slots:
		_ensure_static_slots_once()

	if apply_linked_ui:
		_apply_player_linked_ui_layout()

	if refresh_slot_rows:
		_update_all_slot_rows()
		TableSyncHelper.update_table_positions(table_root, _table_spacing, GameLayoutConfig.START_POS)

func _apply_positions(positions: Dictionary) -> void:
	"""Applique TOUTES les positions calculées"""
	var vh = positions["vh"]
	var center_x = positions["center_x"]
	var right_x = positions["right_x"]
	
	table_root.position = Vector2(center_x, vh * GameLayoutConfig.TABLE_Y_RATIO)
	pioche_root.position = Vector2(right_x, vh * GameLayoutConfig.TABLE_Y_RATIO)
	
	quitter_button.text = LanguageManager.ui_text(UI_GAME_QUIT_BUTTON_KEY, "Quit")
	quitter_button.size = Vector2(GameLayoutConfig.QUITTER_WIDTH, GameLayoutConfig.QUITTER_HEIGHT)
	quitter_button.position = Vector2(right_x - GameLayoutConfig.QUITTER_OFFSET_X, GameLayoutConfig.QUITTER_OFFSET_Y)

func _apply_language_to_game_ui() -> void:
	quitter_button.text = LanguageManager.ui_text(UI_GAME_QUIT_BUTTON_KEY, "Quit")

func _on_language_changed(_language_code: String) -> void:
	_apply_language_to_game_ui()

func _apply_timebar_layout() -> void:
	TimebarUtil.apply_layout(_timebar_state, p1_banc_anchor.global_position)

func _apply_game_message_layout() -> void:
	GameMessage.apply_layout(_game_message_state, p1_main_anchor.global_position)

func _apply_player_linked_ui_layout() -> void:
	_apply_timebar_layout()
	_apply_game_message_layout()
	DeckCountUtil.update_positions(_deck_count_state, self, player1_root, player2_root)

func _init_ui() -> void:
	"""Initialise l'UI"""
	GameMessage.ensure_ui(_game_message_state, self, Callable(self, "_on_message_timeout"))

	TimebarUtil.ensure_ui(_timebar_state, self)
	DeckCountUtil.ensure_ui(_deck_count_state, self)
	DeckCountUtil.reset_counts(_deck_count_state)
	_apply_player_linked_ui_layout()

# ============= SETUP JOUEURS ET SLOTS (SIMPLIFIÉ) =============

func _setup_player(player: Node, player_id: int, create_slots: bool = false) -> void:
	"""Setup unique pour création/repositionnement d'un joueur"""
	var layout = GameLayoutConfig.get_player_layout(player_id, _positions_cache, _slot_spacing)
	
	player.position = Vector2(0, layout["root_y"])
	player.get_node("Deck").position = Vector2(layout["deck_x"], 0)
	player.get_node("Main").position = Vector2(layout["main_x"], 0)
	player.get_node("Banc").position = Vector2(layout["banc_x"], 0)
	
	if create_slots:
		_create_player_slots(player, player_id)

func _create_player_slots(player: Node, player_id: int) -> void:
	"""Crée tous les slots d'un joueur"""
	_create_slot(player.get_node("Deck"), "%d:DECK:1" % player_id, START_POS)
	_create_slots_row(player.get_node("Main"), player_id, "HAND", GameLayoutConfig.MAIN_COUNT)
	_create_slots_row(player.get_node("Banc"), player_id, "BENCH", GameLayoutConfig.BANC_COUNT)

func _create_slots_row(parent: Node, player_id: int, slot_type: String, count: int) -> void:
	"""Crée une rangée de slots"""
	for i in range(count):
		var slot_id = "%d:%s:%d" % [player_id, slot_type, i + 1]
		_create_slot(parent, slot_id, START_POS + Vector2(i * _slot_spacing, 0))

func _create_slot(parent: Node, slot_id: String, pos: Vector2) -> void:
	"""Crée ou récupère un slot - Évite les doublons"""
	if slots_by_id.has(slot_id):
		return
	
	var node_name = SlotIdHelper.slot_node_name(slot_id)
	
	if parent.has_node(node_name):
		var existing = parent.get_node(node_name)
		slots_by_id[slot_id] = existing
		return
	
	var slot = slot_scene.instantiate()
	slot.name = node_name
	slot.slot_id = slot_id
	slot.position = pos
	parent.add_child(slot)
	slots_by_id[slot_id] = slot

# ============= LAYOUT SIGNALS & RESIZE (SIMPLIFIÉ) =============

func _connect_layout_signals() -> void:
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)

func _on_viewport_size_changed() -> void:
	_relayout_board()

func _relayout_board() -> void:
	_reflow_layout(false, true, true)

func _update_all_slot_rows() -> void:
	"""Met à jour positions de tous les slots"""
	for player_id in [1, 2]:
		_update_row_positions(player_id, "HAND", GameLayoutConfig.MAIN_COUNT)
		_update_row_positions(player_id, "BENCH", GameLayoutConfig.BANC_COUNT)

func _update_row_positions(player_id: int, slot_type: String, count: int) -> void:
	"""Met à jour les positions d'une rangée de slots"""
	for i in range(count):
		var slot_id = "%d:%s:%d" % [player_id, slot_type, i + 1]
		var slot = slots_by_id.get(slot_id)
		if slot:
			slot.position = START_POS + Vector2(i * _slot_spacing, 0)
			if slot.has_method("invalidate_rect_cache"):
				slot.call("invalidate_rect_cache")

# ============= EVENTS & RESPONSES (ORIGINAL COMPLET) =============

func _on_evt(type: String, data: Dictionary) -> void:
	if not slots_ready:
		pending_events.append({"type": type, "data": data})
		return

	match type:
		"start_game":
			GameEventHandler.handle_start_game(data, self)
		"table_sync":
			GameEventHandler.handle_table_sync(data, self)
		"slot_state":
			GameEventHandler.handle_slot_state(data, self)
		"state_snapshot":
			GameEventHandler.handle_state_snapshot(data, self)
		"show_game_message":
			_show_game_feedback(data)
		"game_end":
			GameEventHandler.handle_game_end(data, self)
		"turn_update":
			_set_turn_timer(data)
		"opponent_disconnected":
			GameEventHandler.handle_opponent_disconnected(data, self)
		"opponent_rejoined":
			GameEventHandler.handle_opponent_rejoined(data, self)
		"invite_request":
			GameEventHandler.handle_invite_request(data)
		"invite_response":
			GameEventHandler.handle_invite_response(data)
		"invite_cancelled":
			GameEventHandler.handle_invite_cancelled(data)
		"rematch_declined":
			GameEventHandler.handle_rematch_declined(data)


# ============= RESPONSES =============

func _on_response(_rid: String, type: String, ok: bool, _data: Dictionary, error: Dictionary) -> void:
	GameResponseHandler.handle_response(_rid, type, ok, _data, error, self)

func _on_connection_lost() -> void:
	GameConnectionHandler.on_connection_lost(self)

func _on_connection_restored() -> void:
	GameConnectionHandler.on_connection_restored(self)

func _on_reconnect_failed() -> void:
	GameConnectionHandler.on_reconnect_failed(self)

func _on_server_closed(server_reason: String, close_code: int, raw_reason: String) -> void:
	GameConnectionHandler.on_server_closed(server_reason, close_code, raw_reason, self)


func _request_game_sync() -> void:
	var game_id := String(Global.current_game_id)
	if game_id == "":
		return

	if bool(Global.is_spectator):
		NetworkManager.request(REQ_SPECTATE_GAME, {"game_id": game_id})
	else:
		NetworkManager.request(REQ_JOIN_GAME, {"game_id": game_id})

func _resolve_slot_for_update(slot_id: String, require_allowed_table: bool) -> Variant:
	var slot :Variant= slots_by_id.get(slot_id)
	if slot == null and SlotIdHelper.is_table_slot_id(slot_id):
		if require_allowed_table and not allowed_table_slots.has(slot_id):
			return null
		slot = slots_by_id.get(slot_id)
	return slot

func _apply_slot_cards_update(slot_id: String, slot, arr: Array, count_for_slot: int, animate_on_finalize: bool, clear_slot_first: bool) -> void:
	if clear_slot_first and slot != null and slot.has_method("clear_slot"):
		slot.clear_slot()

	var normalized_count := maxi(0, count_for_slot)
	if slot != null and slot.has_method("set_server_count"):
		slot.call("set_server_count", normalized_count)
	DeckCountUtil.update_from_slot(_deck_count_state, slot_id, normalized_count)
	if slot != null and slot.has_method("begin_server_sync"):
		slot.call("begin_server_sync", animate_on_finalize)

	for i in range(arr.size()):
		var payload = arr[i]
		if payload is Dictionary:
			payload["_array_order"] = i
			CardSyncHelper.apply_card_update(_card_ctx, payload)

	if slot != null and slot.has_method("finalize_server_sync"):
		slot.call("finalize_server_sync")


# ============= GAME END =============

func _on_game_end(data: Dictionary) -> void:
	if _game_end_prompted:
		return
	_game_end_prompted = true
	var popup_msg := Protocol.game_end_popup_message(data, String(Global.username), bool(Global.is_spectator))
	var rematch_allowed := bool(data.get("rematch_allowed", true))
	if _opponent_disconnected:
		rematch_allowed = false
	if bool(Global.is_spectator) or not rematch_allowed:
		PopupUi.show_code(
			PopupUi.MODE_INFO,
			String(popup_msg.get("message_code", "")),
			popup_msg.get("message_params", {}) as Dictionary,
			{
				"ok_action_id": ACTION_GAME_END_LEAVE,
				"game_id": String(Global.current_game_id),
			},
			{"ok_label_key": "UI_LABEL_BACK_LOBBY"}
		)
		return

	PopupUi.show_code(
		PopupUi.MODE_CONFIRM,
		String(popup_msg.get("message_code", "")),
		popup_msg.get("message_params", {}) as Dictionary,
		{
			"yes_action_id": ACTION_GAME_END_LEAVE,
			"no_action_id": ACTION_GAME_END_REMATCH,
			"game_id": String(Global.current_game_id),
		},
		{"yes_label_key": "UI_LABEL_BACK_LOBBY", "no_label_key": "UI_LABEL_REMATCH"}
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

func _resolve_rematch_target_username() -> String:
	var self_name := String(Global.username).strip_edges()
	for player in Global.players_in_game:
		if player is String:
			var player_name := String(player).strip_edges()
			if player_name != "" and player_name != self_name:
				return player_name
		elif player is Dictionary:
			var player_dict := player as Dictionary
			var dict_name := String(player_dict.get("username", "")).strip_edges()
			if dict_name != "" and dict_name != self_name:
				return dict_name
	return ""

func _ack_end_invite_rematch_in_game() -> void:
	var gid := String(Global.current_game_id)
	var source_game_id := gid
	var opponent_name := _resolve_rematch_target_username()
	if gid != "":
		var ack_res := await NetworkManager.request_async(
			REQ_ACK_GAME_END,
			{
				"game_id": gid,
				"intent": ACK_INTENT_REMATCH,
			},
			6.0
		)
		if not bool(ack_res.get("ok", false)):
			var err_val = ack_res.get("error", {})
			var err: Dictionary = err_val if err_val is Dictionary else {}
			PopupUi.show_normalized(PopupUi.MODE_INFO, Protocol.normalize_popup_error(err, Protocol.POPUP_UI_ACTION_IMPOSSIBLE))
			return

	if opponent_name == "":
		PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_INVITE_FAILED)
		return

	Global.current_game_id = ""
	Global.players_in_game = []
	Global.is_spectator = false
	Global.result = {}
	_reset_board_state()

	var invite_payload := {"to": opponent_name}
	if source_game_id != "":
		invite_payload["context"] = REMATCH_CONTEXT
		invite_payload["source_game_id"] = source_game_id
	NetworkManager.request(REQ_INVITE, invite_payload)


# ============= INVALID MOVE =============

func _on_invalid_move(data: Dictionary) -> void:
	var card_id: String = String(data.get("card_id", ""))
	var from_slot_id: String = SlotIdHelper.normalize_slot_id(String(data.get("from_slot_id", "")))
	if card_id == "" or from_slot_id == "":
		return

	var card = CardSyncHelper.get_or_create_card(_card_ctx, card_id)
	var slot = slots_by_id.get(from_slot_id)
	if slot:
		slot.snap_card(card, true)
		card.set_meta("last_slot_id", from_slot_id)

# ============= RESET =============

func _reset_board_state() -> void:
	for s in slots_by_id.values():
		if s and s.has_method("clear_slot"):
			s.clear_slot()
	DeckCountUtil.reset_counts(_deck_count_state)

	TableSyncHelper.sync_table_slots(table_root, slot_scene, slots_by_id, allowed_table_slots, ["0:TABLE:1"], _table_spacing, START_POS)

	for k in cards.keys():
		var c = cards[k]
		if is_instance_valid(c):
			c.queue_free()
	cards.clear()

	pending_events.clear()
	slots_ready = true

# ============= UI MESSAGES =============

func _show_game_feedback(ui_message: Dictionary) -> void:
	"""Affiche un message de jeu"""
	var rule_msg := GameMessage.normalize_rule_message(ui_message)
	if not rule_msg.is_empty():
		_display_rule_message(rule_msg)
		return

	var popup_msg := Protocol.normalize_popup_message(ui_message)
	PopupUi.show_normalized(PopupUi.MODE_INFO, popup_msg)

func _display_rule_message(ui_message: Dictionary) -> void:
	"""Affiche et anime le message"""
	if _message_tween and is_instance_valid(_message_tween):
		_message_tween.kill()
	
	GameMessage.show_rule_message(ui_message, _game_message_state)
	var label := GameMessage.get_label(_game_message_state)
	if label != null:
		label.modulate.a = 1.0

func _on_message_timeout() -> void:
	"""Appelé quand le timer du message expire"""
	_hide_message_with_fade()

func _hide_message_with_fade() -> void:
	"""Cache le message avec un fadeout"""
	var label := GameMessage.get_label(_game_message_state)
	if label == null or not label.visible:
		return
	
	if _message_tween and is_instance_valid(_message_tween):
		_message_tween.kill()
	
	_message_tween = create_tween()
	_message_tween.tween_property(label, "modulate:a", 0.0, GameMessage.get_fade_duration())
	await _message_tween.finished
	
	label.visible = false
	label.modulate.a = 1.0

# ============= TIMEBAR =============

func _process(_delta: float) -> void:
	TimebarUtil.update_timebar(_timebar_state, Callable(NetworkManager, "server_now_ms"))

func _set_turn_timer(turn: Dictionary) -> void:
	TimebarUtil.set_turn_timer(_timebar_state, turn, Callable(NetworkManager, "sync_server_clock"))
	TimebarUtil.update_timebar_mode(_timebar_state, bool(Global.is_spectator), String(Global.username))
	TimebarUtil.update_timebar(_timebar_state, Callable(NetworkManager, "server_now_ms"))

# ============= QUITTER =============

func _on_quitter_pressed() -> void:
	PopupUi.show_code(
		PopupUi.MODE_CONFIRM,
		Protocol.POPUP_QUIT_CONFIRM,
		{},
		{
			"yes_action_id": ACTION_QUIT_CANCEL,
			"no_action_id": ACTION_QUIT_CONFIRM,
		},
		{"yes_label_key": "UI_LABEL_CANCEL", "no_label_key": "UI_LABEL_QUIT"}
	)

func _schedule_disconnect_choice(who: String) -> void:
	GameConnectionHandler.schedule_disconnect_choice(who, self)

func _on_popup_action(action_id: String, payload: Dictionary) -> void:
	if action_id == ACTION_NETWORK_RETRY:
		NetworkManager.retry_now()
		return

	var invite_req := Protocol.invite_action_request(action_id, payload)
	if not invite_req.is_empty():
		NetworkManager.request(REQ_INVITE_RESPONSE, invite_req)
		return

	match action_id:
		ACTION_QUIT_CONFIRM, ACTION_PAUSE_LEAVE:
			await _leave_current_and_go_lobby()
		ACTION_GAME_END_LEAVE:
			await _ack_end_and_go_lobby()
		ACTION_GAME_END_REMATCH:
			await _ack_end_invite_rematch_in_game()
		ACTION_REMATCH_DECLINED_LEAVE:
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
	if NetworkManager.connection_lost.is_connected(_on_connection_lost):
		NetworkManager.connection_lost.disconnect(_on_connection_lost)
	if NetworkManager.connection_restored.is_connected(_on_connection_restored):
		NetworkManager.connection_restored.disconnect(_on_connection_restored)
	if NetworkManager.reconnect_failed.is_connected(_on_reconnect_failed):
		NetworkManager.reconnect_failed.disconnect(_on_reconnect_failed)
	if NetworkManager.server_closed.is_connected(_on_server_closed):
		NetworkManager.server_closed.disconnect(_on_server_closed)
	if PopupUi.action_selected.is_connected(_on_popup_action):
		PopupUi.action_selected.disconnect(_on_popup_action)
	if LanguageManager.language_changed.is_connected(_on_language_changed):
		LanguageManager.language_changed.disconnect(_on_language_changed)

	GameMessage.cleanup(_game_message_state)
	TimebarUtil.cleanup(_timebar_state)
	DeckCountUtil.cleanup(_deck_count_state)
	
	if _message_tween and is_instance_valid(_message_tween):
		_message_tween.kill()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if String(Global.current_game_id) != "":
			NetworkManager.request(REQ_ACK_GAME_END, {"game_id": String(Global.current_game_id)})
