# Game.gd
extends Control

# ============= SCENES =============
var slot_scene: PackedScene = preload("res://Scenes/Slot.tscn")
var card_scene: PackedScene = preload("res://Scenes/Carte.tscn")

# ============= CONFIG & HELPERS =============
const Protocol = preload("res://net/Protocol.gd")

# ============= PROTOCOL ALIASES =============
# Alias locaux pour les nodes fils (GameStateHandler/Manager) qui lisent game.REQ_* / game.ACTION_*.
const FLOW_INVITE_REQUEST           := Protocol.POPUP_FLOW_INVITE_REQUEST
const REQ_JOIN_GAME                 := Protocol.REQ_JOIN_GAME
const REQ_SPECTATE_GAME             := Protocol.REQ_SPECTATE_GAME
const REQ_INVITE                    := Protocol.REQ_INVITE
const REQ_INVITE_RESPONSE           := Protocol.REQ_INVITE_RESPONSE
const REQ_ACK_GAME_END              := Protocol.REQ_ACK_GAME_END
const REQ_LEAVE_GAME                := Protocol.REQ_LEAVE_GAME
const REMATCH_CONTEXT               := Protocol.REMATCH_CONTEXT
const ACK_INTENT_REMATCH            := Protocol.ACK_INTENT_REMATCH
const ACTION_GAME_END_LEAVE         := Protocol.ACTION_GAME_END_LEAVE
const ACTION_GAME_END_REMATCH       := Protocol.ACTION_GAME_END_REMATCH
const ACTION_REMATCH_DECLINED_LEAVE := Protocol.ACTION_REMATCH_DECLINED_LEAVE
const ACTION_QUIT_CANCEL            := Protocol.ACTION_QUIT_CANCEL
const ACTION_QUIT_CONFIRM           := Protocol.ACTION_QUIT_CONFIRM
const ACTION_PAUSE_WAIT             := Protocol.ACTION_PAUSE_WAIT
const ACTION_PAUSE_LEAVE            := Protocol.ACTION_PAUSE_LEAVE
const ACTION_NETWORK_RETRY          := Protocol.ACTION_NETWORK_RETRY
const UI_GAME_QUIT_BUTTON_KEY       := Protocol.UI_GAME_QUIT_BUTTON_KEY

# ============= MANAGERS =============
# layout_manager et ui_manager ne sont PAS des membres : ils vivent dans _game_context.
var board_factory:       BoardFactory     = null
var game_state_manager:  GameStateManager = null
var _game_context:       GameContext      = null

# ============= STATE =============
var slots_ready: bool = false
var slots_by_id: Dictionary = {}
var pending_events: Array[Dictionary] = []
var cards: Dictionary = {}
var allowed_table_slots: Dictionary = {}

# ============= UI STATE =============
var _is_changing_scene     := false
var _game_end_prompted     := false
var _leave_sent            := false
var _disconnect_prompt_seq := 0
var _opponent_disconnected := false
var _deck_count_state: Dictionary = DeckCountUtil.create_state()

# ============= LAYOUT STATE =============
var _slot_spacing:    float      = GameLayoutConfig.DEFAULT_SLOT_SPACING
var _positions_cache: Dictionary = {}
var START_POS:        Vector2    = GameLayoutConfig.START_POS

# ============= CARD CONTEXT =============
var _card_ctx: CardContext = null

# ============= UI STATE DICTS =============
var _timebar_state:      Dictionary = TimebarUtil.create_state()
var _game_message_state: Dictionary = GameMessage.create_ui_state()

# ============= NODES =============
@onready var player1_root:   Node2D = $Board/Player1
@onready var player2_root:   Node2D = $Board/Player2
@onready var p1_main_anchor: Node2D = $Board/Player1/Main
@onready var p1_banc_anchor: Node2D = $Board/Player1/Banc
@onready var pioche_root:    Node2D = $Board/Pioche
@onready var table_root:     Node2D = $Board/Table
@onready var quitter_button: Button = $Quitter

# ============= LIFECYCLE =============

func _ready() -> void:
    _connect_layout_signals()

    board_factory = preload("res://game/factories/BoardFactory.gd").new()
    board_factory.setup(slot_scene, slots_by_id, START_POS)

    _card_ctx = preload("res://game/card/CardContext.gd").new(cards, card_scene, slots_by_id, self)

    var layout_manager: GameLayoutManager = preload("res://game/managers/GameLayoutManager.gd").new()
    layout_manager.setup(self, {
        "player1_root":   player1_root,
        "player2_root":   player2_root,
        "table_root":     table_root,
        "pioche_root":    pioche_root,
        "quitter_button": quitter_button,
        "p1_banc_anchor": p1_banc_anchor,
        "p1_main_anchor": p1_main_anchor,
    }, {
        "timebar":      _timebar_state,
        "game_message": _game_message_state,
        "deck_count":   _deck_count_state,
    }, GameLayoutConfig)

    var ui_manager: GameUIManager = preload("res://game/managers/GameUIManager.gd").new()
    ui_manager.setup(self, {
        "game_message": _game_message_state,
        "timebar":      _timebar_state,
        "deck_count":   _deck_count_state,
    })

    _game_context = preload("res://game/types/GameContext.gd").new(self)
    _game_context.card_context    = _card_ctx
    _game_context.ui_manager      = ui_manager
    _game_context.layout_manager  = layout_manager


    game_state_manager = preload("res://game/managers/GameStateManager.gd").new(_game_context)

    _init_layout()
    _connect_network_signals()

    # Connect quit button and popup actions
    if quitter_button != null:
        _safe_connect(quitter_button.pressed, self, "_on_quitter_pressed")

    if not PopupUi.action_selected.is_connected(_on_popup_action):
        PopupUi.action_selected.connect(_on_popup_action)

    PopupUi.hide_and_reset()
    _game_context.layout_manager.apply_language()

    if GameSession.current_game_id != "":
        var game_id: String = GameSession.current_game_id
        if GameSession.is_spectator:
            ClientAPI.spectate_game(game_id)
        else:
            ClientAPI.join_game(game_id)

    await get_tree().process_frame
    slots_ready = true
    _game_context.slots_ready = true
    _game_context.ui_manager.init_ui_components(Callable(_game_context.ui_manager, "on_message_timeout"))
    _game_context.layout_manager.apply_ui_layout()
    _game_context.ui_manager.update_timebar(Callable(NetworkManager, "server_now_ms"))

    board_factory.ensure_static_slots_once(pioche_root)

    for event in pending_events:
        _on_evt(event.get("type", ""), event.get("data", {}))
    pending_events.clear()

# ============= LAYOUT =============

func _do_layout(create_slots: bool, apply_ui: bool, refresh_rows: bool) -> void:
    if _game_context == null or _game_context.layout_manager == null:
        return
    var ctx: Dictionary = _game_context.layout_manager.compute_layout()
    _positions_cache = ctx
    _slot_spacing = float(ctx.get("slot_spacing", GameLayoutConfig.DEFAULT_SLOT_SPACING))
    _game_context.layout_manager.apply_layout(ctx)
    _apply_players_layout(create_slots)
    _ensure_static_slots_once()
    if refresh_rows:
        board_factory.update_all_slot_rows(_slot_spacing)
    if apply_ui:
        _game_context.layout_manager.apply_ui_layout()

func _init_layout() -> void:
    _do_layout(true, false, false)

func _relayout_board() -> void:
    _do_layout(false, true, true)

func _apply_players_layout(create_slots: bool) -> void:
    _setup_player(player1_root, 1, create_slots)
    _setup_player(player2_root, 2, create_slots)

func _ensure_static_slots_once() -> void:
    board_factory.ensure_static_slots_once(pioche_root)

func _setup_player(player: Node, player_id: int, create_slots: bool = false) -> void:
    var layout := GameLayoutConfig.get_player_layout(player_id, _positions_cache, _slot_spacing)
    player.position                  = Vector2(0, layout["root_y"])
    player.get_node("Deck").position = Vector2(layout["deck_x"], 0)
    player.get_node("Main").position = Vector2(layout["main_x"], 0)
    player.get_node("Banc").position = Vector2(layout["banc_x"], 0)
    if create_slots:
        board_factory.create_player_slots(player, player_id, _slot_spacing)

# ============= SIGNAUX =============

func _safe_connect(sig: Signal, target: Object, method: String) -> void:
    if target == null or not target.has_method(method):
        return
    var c := Callable(target, method)
    if not sig.is_connected(c):
        sig.connect(c)

func _connect_network_signals() -> void:
   _safe_connect(ClientAPI.evt_start_game,             game_state_manager, "_on_evt_start_game")
   _safe_connect(ClientAPI.evt_state_snapshot,         game_state_manager, "_on_evt_state_snapshot")
   _safe_connect(ClientAPI.evt_slot_state,             game_state_manager, "_on_evt_slot_state")
   _safe_connect(ClientAPI.evt_table_sync,             game_state_manager, "_on_evt_table_sync")
   _safe_connect(ClientAPI.evt_turn_update,            game_state_manager, "_on_evt_turn_update")
   _safe_connect(ClientAPI.evt_game_end,               game_state_manager, "_on_evt_game_end")
   _safe_connect(ClientAPI.evt_game_message,           game_state_manager, "_on_evt_game_message")
   _safe_connect(ClientAPI.evt_opponent_disconnected,  game_state_manager, "_on_evt_opponent_disconnected")
   _safe_connect(ClientAPI.evt_opponent_rejoined,      game_state_manager, "_on_evt_opponent_rejoined")
   _safe_connect(ClientAPI.evt_invite_received,        game_state_manager, "_on_evt_invite_received")
   _safe_connect(ClientAPI.evt_invite_response,        game_state_manager, "_on_evt_invite_response")
   _safe_connect(ClientAPI.evt_invite_cancelled,       game_state_manager, "_on_evt_invite_cancelled")
   _safe_connect(ClientAPI.evt_rematch_declined,       game_state_manager, "_on_evt_rematch_declined")
   _safe_connect(ClientAPI.join_game_ok,               game_state_manager, "_on_join_game_ok")
   _safe_connect(ClientAPI.move_ok,                    game_state_manager, "_on_move_ok")
   _safe_connect(ClientAPI.move_failed,                game_state_manager, "_on_move_failed")
   _safe_connect(ClientAPI.invite_sent,                game_state_manager, "_on_invite_sent")
   _safe_connect(ClientAPI.invite_send_failed,         game_state_manager, "_on_invite_send_failed")
   _safe_connect(ClientAPI.login_ok,                   game_state_manager, "_on_login_ok")
   _safe_connect(ClientAPI.connection_lost,            game_state_manager, "on_connection_lost")
   _safe_connect(ClientAPI.connection_restored,        game_state_manager, "on_connection_restored")
   _safe_connect(ClientAPI.reconnect_failed,           game_state_manager, "on_reconnect_failed")
   _safe_connect(ClientAPI.server_closed,              game_state_manager, "on_server_closed")

func _connect_layout_signals() -> void:
    var vp := get_viewport()
    if vp != null and not vp.size_changed.is_connected(_on_viewport_size_changed):
        vp.size_changed.connect(_on_viewport_size_changed)

func _on_viewport_size_changed() -> void:
    _relayout_board()

# ============= EVENTS =============

func _on_evt(type: String, data: Dictionary) -> void:
    if game_state_manager != null:
        game_state_manager.handle_event(type, data)

func _reset_deck_counts() -> void:
    if typeof(_deck_count_state) == TYPE_DICTIONARY:
        DeckCountUtil.reset_counts(_deck_count_state)

# ============= TIMEBAR =============

func _process(_delta: float) -> void:
    if _game_context != null and _game_context.ui_manager != null:
        _game_context.ui_manager.update_timebar(Callable(ClientAPI, "server_now_ms"))

func _set_turn_timer(turn: Dictionary) -> void:
    if _game_context != null and _game_context.ui_manager != null:
        _game_context.ui_manager.set_turn_timer(
            turn,
            Callable(NetworkManager, "sync_server_clock"),
            GameSession.is_spectator,
            String(Global.username)
        )

# ============= QUITTER =============

func _on_quitter_pressed() -> void:
    PopupRouter.show_quit_confirm()

func _on_game_end(data: Dictionary) -> void:
    if _game_end_prompted:
        return
    _game_end_prompted = true
    GameSession.end_game(data.get("result", {}))
    var rematch_allowed := bool(data.get("rematch_allowed", true)) and not _opponent_disconnected
    PopupRouter.show_game_end(
        data, String(Global.username),
        GameSession.is_spectator, rematch_allowed,
        GameSession.current_game_id
    )

func _show_pause_choice(who: String) -> void:
    PopupRouter.show_pause_disconnect_choice(who)

func _schedule_disconnect_choice(who: String) -> void:
    _disconnect_prompt_seq += 1
    var seq := _disconnect_prompt_seq
    get_tree().create_timer(5.0).timeout.connect(func() -> void:
        if seq != _disconnect_prompt_seq or not _opponent_disconnected:
            return
        _show_pause_choice(who)
    )

func _on_popup_action(action_id: String, payload: Dictionary) -> void:
    if action_id == ACTION_NETWORK_RETRY:
        NetworkManager.retry_now()
        return

    var invite_req := MessageCatalog.invite_action_request(action_id, payload)
    if not invite_req.is_empty():
        NetworkManager.request(REQ_INVITE_RESPONSE, invite_req)
        return

    match action_id:
        ACTION_QUIT_CONFIRM, ACTION_PAUSE_LEAVE:
            _leave_current_and_go_lobby()
        ACTION_GAME_END_LEAVE:
            if game_state_manager != null and game_state_manager.has_method("_ack_end_and_go_lobby"):
                game_state_manager._ack_end_and_go_lobby()
        ACTION_GAME_END_REMATCH:
            if game_state_manager != null and game_state_manager.has_method("_ack_end_invite_rematch_in_game"):
                game_state_manager._ack_end_invite_rematch_in_game()
        ACTION_REMATCH_DECLINED_LEAVE:
            if game_state_manager != null and game_state_manager.has_method("_ack_end_and_go_lobby"):
                game_state_manager._ack_end_and_go_lobby()

func _leave_current_and_go_lobby() -> void:
    if _leave_sent:
        return
    _leave_sent = true
    var gid: String = GameSession.current_game_id
    if gid != "":
        if GameSession.is_game_ended() or GameSession.is_spectator:
            ClientAPI.request_async(REQ_ACK_GAME_END, {"game_id": gid}, 4.0)
        else:
            ClientAPI.leave_game(gid)
    GameSession.reset_game_state()
    SceneManager.go_to_lobby()

func _go_to_lobby_safe() -> void:
    if _is_changing_scene:
        return
    _is_changing_scene = true
    SceneManager.go_to_lobby()

# ============= CLEANUP =============

func _exit_tree() -> void:
    if GameSession.current_game_id != "":
        NetworkManager.request(REQ_ACK_GAME_END, {"game_id": GameSession.current_game_id})

    if game_state_manager != null:
        for pair in [
            [NetworkManager.evt,                 "handle_event"],
            [NetworkManager.response,            "on_response"],
            [NetworkManager.connection_lost,     "on_connection_lost"],
            [NetworkManager.connection_restored, "on_connection_restored"],
            [NetworkManager.reconnect_failed,    "on_reconnect_failed"],
            [NetworkManager.server_closed,       "on_server_closed"],
        ]:
            var s: Signal = pair[0]
            var m: String = pair[1]
            if game_state_manager.has_method(m):
                var c := Callable(game_state_manager, m)
                if s.is_connected(c):
                    s.disconnect(c)

    if PopupUi.action_selected.is_connected(_on_popup_action):
        PopupUi.action_selected.disconnect(_on_popup_action)

    if _game_context != null and _game_context.ui_manager != null:
        _game_context.ui_manager.cleanup()

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST and GameSession.current_game_id != "":
        NetworkManager.request(REQ_ACK_GAME_END, {"game_id": GameSession.current_game_id})
