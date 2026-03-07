# Game.gd - Layout simplifié + Handlers complets du code original

extends Control

# ============= SCENES =============
var slot_scene: PackedScene = preload("res://Client/Scenes/Slot.tscn")
var card_scene: PackedScene = preload("res://Client/Scenes/Carte.tscn")

# ============= CONFIG & HELPERS =============
const Protocol = preload("res://Client/net/Protocol.gd")
# ============= CONSTANTS =============
const FLOW_INVITE_REQUEST := Protocol.POPUP_FLOW_INVITE_REQUEST
const REMATCH_CONTEXT := "rematch"
const ACK_INTENT_REMATCH := "rematch"
const REQ_JOIN_GAME := "join_game"
const REQ_SPECTATE_GAME := "spectate_game"
const REQ_INVITE := "invite"
const REQ_INVITE_RESPONSE := "invite_response"
const REQ_ACK_GAME_END := "ack_game_end"
const REQ_LEAVE_GAME := "leave_game"

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
var layout_manager = null
var board_factory = null
var game_state_handler = null

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

	# Setup layout manager
	layout_manager = preload("res://Client/game/GameLayoutManager.gd").new()
	layout_manager.setup(self, {
		"player1_root": player1_root,
		"player2_root": player2_root,
		"table_root": table_root,
		"pioche_root": pioche_root,
		"quitter_button": quitter_button,
	}, GameLayoutConfig)

	# Setup board factory
	board_factory = preload("res://Client/game/BoardFactory.gd").new()
	board_factory.setup(slot_scene, slots_by_id, START_POS)

	# Setup game state handler (event/response handling)
	game_state_handler = preload("res://Client/game/GameStateHandler.gd").new()
	game_state_handler.setup(self)

	_init_layout()
	
	_card_ctx = {
		"cards": cards,
		"card_scene": card_scene,
		"slots_by_id": slots_by_id,
		"root": self,
	}

	# ===== CONNECTER LES SIGNAUX RÉSEAU =====
	# Route events/responses to the extracted GameStateHandler
	if not NetworkManager.evt.is_connected(game_state_handler.handle_event):
		NetworkManager.evt.connect(game_state_handler.handle_event)
	if not NetworkManager.response.is_connected(game_state_handler.on_response):
		NetworkManager.response.connect(game_state_handler.on_response)
	# Connect connection-related signals to the handler when available
	if game_state_handler != null and game_state_handler.has_method("on_connection_lost"):
		if not NetworkManager.connection_lost.is_connected(game_state_handler.on_connection_lost):
			NetworkManager.connection_lost.connect(game_state_handler.on_connection_lost)
	if game_state_handler != null and game_state_handler.has_method("on_connection_restored"):
		if not NetworkManager.connection_restored.is_connected(game_state_handler.on_connection_restored):
			NetworkManager.connection_restored.connect(game_state_handler.on_connection_restored)
	if game_state_handler != null and game_state_handler.has_method("on_reconnect_failed"):
		if not NetworkManager.reconnect_failed.is_connected(game_state_handler.on_reconnect_failed):
			NetworkManager.reconnect_failed.connect(game_state_handler.on_reconnect_failed)
	if game_state_handler != null and game_state_handler.has_method("on_server_closed"):
		if not NetworkManager.server_closed.is_connected(game_state_handler.on_server_closed):
			NetworkManager.server_closed.connect(game_state_handler.on_server_closed)
	if not PopupUi.action_selected.is_connected(_on_popup_action):
		PopupUi.action_selected.connect(_on_popup_action)

	
	if not quitter_button.pressed.is_connected(_on_quitter_pressed):
		quitter_button.pressed.connect(_on_quitter_pressed)
	
	PopupUi.hide_and_reset()
	_apply_language_to_game_ui()

	if String(Global.current_game_id) != "":
		if game_state_handler != null and game_state_handler.has_method("_request_game_sync"):
			game_state_handler._request_game_sync()

	await get_tree().process_frame
	slots_ready = true
	TimebarUtil.update_timebar(_timebar_state, Callable(NetworkManager, "server_now_ms"))

	board_factory.ensure_static_slots_once(pioche_root)

	for event in pending_events:
		_on_evt(event.get("type", ""), event.get("data", {}))
	pending_events.clear()

# ============= LAYOUT INITIALIZATION (SIMPLIFIÉ) =============

func _init_layout() -> void:
	"""Initialise layout + slots fixes (sans reflow rows)"""
	if layout_manager != null:
		var ctx :Variant= layout_manager.compute_layout()
		_apply_layout_context(ctx)
		_apply_players_layout(true)
		if true:
			_ensure_static_slots_once()
	else:
		_reflow_layout(true, false, false)
	_init_ui()

func _compute_layout_context() -> Dictionary:
	if layout_manager != null:
		return layout_manager.compute_layout()
	return {}

func _apply_layout_context(ctx: Dictionary) -> void:
	# Always update local cache/spacing so other functions can use it
	_positions_cache = ctx
	_slot_spacing = float(ctx.get("slot_spacing", GameLayoutConfig.DEFAULT_SLOT_SPACING))
	if layout_manager != null:
		layout_manager.apply_layout(ctx)
	else:
		_apply_positions(_positions_cache)

func _apply_players_layout(create_slots: bool) -> void:
	_setup_player(player1_root, 1, create_slots)
	_setup_player(player2_root, 2, create_slots)

func _ensure_static_slots_once() -> void:
	board_factory.ensure_static_slots_once(pioche_root)

func _reflow_layout(create_slots: bool, apply_linked_ui: bool, refresh_slot_rows: bool) -> void:
	# Use GameLayoutManager as the authoritative reflow implementation
	layout_manager.reflow_layout(create_slots, apply_linked_ui, refresh_slot_rows, Callable(self, "_apply_players_layout"))
	if create_slots:
		_ensure_static_slots_once()
	return

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
		board_factory.create_player_slots(player, player_id, _slot_spacing)

# Slot creation and rows are now handled exclusively by BoardFactory

func _update_all_slot_rows() -> void:
	"""Met à jour positions de tous les slots"""
	board_factory.update_all_slot_rows(_slot_spacing)

func _update_row_positions(player_id: int, slot_type: String, count: int) -> void:
	"""Met à jour les positions d'une rangée de slots"""
	board_factory.update_row_positions(player_id, slot_type, count, _slot_spacing)

# ============= LAYOUT SIGNALS & RESIZE (SIMPLIFIÉ) =============

func _connect_layout_signals() -> void:
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)

func _on_viewport_size_changed() -> void:
	_relayout_board()

func _relayout_board() -> void:
	_reflow_layout(false, true, true)

# ============= EVENTS & RESPONSES (ORIGINAL COMPLET) =============

func _on_evt(type: String, data: Dictionary) -> void:
	# Directly forward all events to the GameStateHandler (migration complete)
	game_state_handler.handle_event(type, data)

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

func _show_pause_choice(who: String) -> void:
	PopupUi.show_code(
		PopupUi.MODE_CONFIRM,
		Protocol.POPUP_OPPONENT_DISCONNECTED_CHOICE,
		{"name": who},
		{
			"yes_action_id": ACTION_PAUSE_WAIT,
			"no_action_id": ACTION_PAUSE_LEAVE,
		},
		{"yes_label_key": "UI_LABEL_WAIT", "no_label_key": "UI_LABEL_BACK_LOBBY"}
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
		_show_pause_choice(who)
	)

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
			if game_state_handler != null and game_state_handler.has_method("_ack_end_and_go_lobby"):
				await game_state_handler._ack_end_and_go_lobby()
		ACTION_GAME_END_REMATCH:
			if game_state_handler != null and game_state_handler.has_method("_ack_end_invite_rematch_in_game"):
				await game_state_handler._ack_end_invite_rematch_in_game()
		ACTION_REMATCH_DECLINED_LEAVE:
			if game_state_handler != null and game_state_handler.has_method("_ack_end_and_go_lobby"):
				await game_state_handler._ack_end_and_go_lobby()
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

	if game_state_handler != null and game_state_handler.has_method("handle_event") and NetworkManager.evt.is_connected(game_state_handler.handle_event):
		NetworkManager.evt.disconnect(game_state_handler.handle_event)
	if game_state_handler != null and game_state_handler.has_method("on_response") and NetworkManager.response.is_connected(game_state_handler.on_response):
		NetworkManager.response.disconnect(game_state_handler.on_response)
	if game_state_handler != null and game_state_handler.has_method("on_connection_lost") and NetworkManager.connection_lost.is_connected(game_state_handler.on_connection_lost):
		NetworkManager.connection_lost.disconnect(game_state_handler.on_connection_lost)
	if game_state_handler != null and game_state_handler.has_method("on_connection_restored") and NetworkManager.connection_restored.is_connected(game_state_handler.on_connection_restored):
		NetworkManager.connection_restored.disconnect(game_state_handler.on_connection_restored)
	if game_state_handler != null and game_state_handler.has_method("on_reconnect_failed") and NetworkManager.reconnect_failed.is_connected(game_state_handler.on_reconnect_failed):
		NetworkManager.reconnect_failed.disconnect(game_state_handler.on_reconnect_failed)
	if game_state_handler != null and game_state_handler.has_method("on_server_closed") and NetworkManager.server_closed.is_connected(game_state_handler.on_server_closed):
		NetworkManager.server_closed.disconnect(game_state_handler.on_server_closed)
	if PopupUi.action_selected.is_connected(_on_popup_action):
		PopupUi.action_selected.disconnect(_on_popup_action)


	GameMessage.cleanup(_game_message_state)
	TimebarUtil.cleanup(_timebar_state)
	DeckCountUtil.cleanup(_deck_count_state)
	
	if _message_tween and is_instance_valid(_message_tween):
		_message_tween.kill()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if String(Global.current_game_id) != "":
			NetworkManager.request(REQ_ACK_GAME_END, {"game_id": String(Global.current_game_id)})
