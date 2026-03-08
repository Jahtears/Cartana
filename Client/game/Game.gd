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
var _game_end_prompted := false  # Used by GameStateHandler
var _leave_sent := false
var _disconnect_prompt_seq := 0
var _opponent_disconnected := false
var _network_disconnected := false  # Used by GameStateHandler
var _deck_count_state: Dictionary = DeckCountUtil.create_state()
# ============= LAYOUT STATE =============
var _slot_spacing: float = GameLayoutConfig.DEFAULT_SLOT_SPACING
var _table_spacing: int = GameLayoutConfig.TABLE_SPACING  # Used by GameStateHandler and TableSyncHelper
var _positions_cache: Dictionary = {}
var layout_manager = null
var board_factory = null
var game_state_handler = null
var ui_manager = null

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
var _card_ctx: CardContext = null

# ============= TIMEBAR STATE =============
var _timebar_state: Dictionary = TimebarUtil.create_state()
var _game_message_state: Dictionary = GameMessage.create_ui_state()

# ============= LIFECYCLE =============

func _ready() -> void:
	_connect_layout_signals()

	# Setup layout manager with UI nodes and states
	layout_manager = preload("res://Client/game/GameLayoutManager.gd").new()
	layout_manager.setup(self, {
		"player1_root": player1_root,
		"player2_root": player2_root,
		"table_root": table_root,
		"pioche_root": pioche_root,
		"quitter_button": quitter_button,
		"p1_banc_anchor": p1_banc_anchor,
		"p1_main_anchor": p1_main_anchor,
	}, {
		"timebar": _timebar_state,
		"game_message": _game_message_state,
		"deck_count": _deck_count_state,
	}, GameLayoutConfig)

	# Setup board factory
	board_factory = preload("res://Client/game/BoardFactory.gd").new()
	board_factory.setup(slot_scene, slots_by_id, START_POS)

	# Setup game state handler (event/response handling)
	game_state_handler = preload("res://Client/game/GameStateHandler.gd").new()
	game_state_handler.setup(self)

	# Setup UI manager
	ui_manager = preload("res://Client/game/GameUIManager.gd").new()
	ui_manager.setup(self, {
		"game_message": _game_message_state,
		"timebar": _timebar_state,
		"deck_count": _deck_count_state,
	})

	_init_layout()
	
	_card_ctx = CardContext.new(cards, card_scene, slots_by_id, self)

	# ===== CONNECTER LES SIGNAUX RÉSEAU =====
	_connect_network_signals()
	
	PopupUi.hide_and_reset()
	layout_manager.apply_language()

	if String(Global.current_game_id) != "" and game_state_handler != null:
		game_state_handler._request_game_sync()

	await get_tree().process_frame
	slots_ready = true
	ui_manager.init_ui_components(Callable(ui_manager, "on_message_timeout"))
	
	# Apply UI layout after UI components are created
	if layout_manager != null:
		layout_manager.apply_ui_layout()
	
	ui_manager.update_timebar(Callable(NetworkManager, "server_now_ms"))

	board_factory.ensure_static_slots_once(pioche_root)

	for event in pending_events:
		_on_evt(event.get("type", ""), event.get("data", {}))
	pending_events.clear()

# ============= LAYOUT INITIALIZATION (SIMPLIFIÉ) =============

func _do_layout(create_slots: bool, apply_ui: bool, refresh_rows: bool) -> void:
	"""Centralised layout computation and application
	
	Args:
		create_slots: Whether to create/recreate player slots
		apply_ui: Whether to apply UI layout (timebar, messages, etc)
		refresh_rows: Whether to refresh slot row positions
	"""
	if layout_manager == null:
		return
	
	var ctx: Dictionary = layout_manager.compute_layout()
	_positions_cache = ctx
	_slot_spacing = float(ctx.get("slot_spacing", GameLayoutConfig.DEFAULT_SLOT_SPACING))
	layout_manager.apply_layout(ctx)
	_apply_players_layout(create_slots)
	_ensure_static_slots_once()
	
	if refresh_rows:
		board_factory.update_all_slot_rows(_slot_spacing)
	
	if apply_ui:
		layout_manager.apply_ui_layout()

func _init_layout() -> void:
	"""Initialise layout + UI"""
	_do_layout(true, false, false)

func _compute_layout_context() -> Dictionary:
	if layout_manager != null:
		return layout_manager.compute_layout()
	return {}

func _apply_players_layout(create_slots: bool) -> void:
	_setup_player(player1_root, 1, create_slots)
	_setup_player(player2_root, 2, create_slots)

func _ensure_static_slots_once() -> void:
	board_factory.ensure_static_slots_once(pioche_root)

func _relayout_board() -> void:
	_do_layout(false, true, true)

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

# ============= LAYOUT SIGNALS & RESIZE (SIMPLIFIÉ) =============

func _safe_connect(sig: Signal, target: Object, method: String) -> void:
	"""Helper: Safe signal connection with existence check and deduplication"""
	if target == null:
		return
	if not target.has_method(method):
		return
	var callable := Callable(target, method)
	if not sig.is_connected(callable):
		sig.connect(callable)

func _connect_network_signals() -> void:
	"""Extract all network signal connections to a single method"""
	_safe_connect(NetworkManager.evt,               game_state_handler, "handle_event")
	_safe_connect(NetworkManager.response,          game_state_handler, "on_response")
	_safe_connect(NetworkManager.connection_lost,   game_state_handler, "on_connection_lost")
	_safe_connect(NetworkManager.connection_restored, game_state_handler, "on_connection_restored")
	_safe_connect(NetworkManager.reconnect_failed,  game_state_handler, "on_reconnect_failed")
	_safe_connect(NetworkManager.server_closed,     game_state_handler, "on_server_closed")
	_safe_connect(PopupUi.action_selected,          self,               "_on_popup_action")
	_safe_connect(quitter_button.pressed,           self,               "_on_quitter_pressed")

func _connect_layout_signals() -> void:
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)

func _on_viewport_size_changed() -> void:
	_relayout_board()


# ============= EVENTS & RESPONSES (ORIGINAL COMPLET) =============

func _on_evt(type: String, data: Dictionary) -> void:
	# Directly forward all events to the GameStateHandler (migration complete)
	game_state_handler.handle_event(type, data)

# ============= UI MESSAGES =============

# Migrées vers GameUIManager.gd - voir show_game_feedback(), display_rule_message(), etc.

# ============= TIMEBAR =============

func _process(_delta: float) -> void:
	if ui_manager != null:
		ui_manager.update_timebar(Callable(NetworkManager, "server_now_ms"))

func _set_turn_timer(turn: Dictionary) -> void:
	if ui_manager != null:
		ui_manager.set_turn_timer(turn, Callable(NetworkManager, "sync_server_clock"), bool(Global.is_spectator), String(Global.username))

# ============= QUITTER =============

func _on_quitter_pressed() -> void:
	PopupUi.show_code(
		PopupUi.MODE_CONFIRM,
		Protocol.POPUP_QUIT_CONFIRM,
		{},
		{},
		{"yes_action_id": ACTION_QUIT_CANCEL, "no_action_id": ACTION_QUIT_CONFIRM, "yes_label_key": "UI_LABEL_CANCEL", "no_label_key": "UI_LABEL_QUIT"}
	)

func _show_pause_choice(who: String) -> void:
	PopupUi.show_code(
		PopupUi.MODE_CONFIRM,
		Protocol.POPUP_OPPONENT_DISCONNECTED_CHOICE,
		{"name": who},
		{},
		{"yes_action_id": ACTION_PAUSE_WAIT, "no_action_id": ACTION_PAUSE_LEAVE, "yes_label_key": "UI_LABEL_WAIT", "no_label_key": "UI_LABEL_BACK_LOBBY"}
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

	# Cleanup managers
	if ui_manager != null:
		ui_manager.cleanup()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if String(Global.current_game_id) != "":
			NetworkManager.request(REQ_ACK_GAME_END, {"game_id": String(Global.current_game_id)})
