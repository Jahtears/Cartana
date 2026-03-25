
# Client/game/managers/GameStateManager.gd
#
# ROUTAGE DES MESSAGES — règle absolue :
#
#   RULE_*  → événement "show_game_message"
#             → _show_game_feedback()
#             → GameUIManager.show_game_feedback()
#             → GameMessage.normalize_rule_message()   (filtre RULE_* strict)
#             → GameMessage label (panneau in-game)
#
#   POPUP_* → événements métier (invite_request, opponent_disconnected, game_end…)
#             → _on_evt_*() → context.game_node._on_*()
#             → Game.gd → PopupUi.* / PopupRouter.*
#             → WindowPopup
#
#   Réponses réseau :
#     move_request  → _on_move_ok() / _on_move_failed()
#     invite        → _on_invite_sent() / _on_invite_send_failed()
#     login         → _on_login_ok()

extends RefCounted
class_name GameStateManager

const Protocol = preload("res://net/Protocol.gd")

# ============= CONSTANTS =============
const REQ_INVITE := "invite"

# ============= PROPERTIES =============
var context: GameContext = null
var _board_sync_service: BoardSyncService = null
var _waiting_for_reauth := false

# ============= LIFECYCLE =============
func _init(game_context: GameContext) -> void:
    context = game_context
    if context != null and context.card_context != null:
        _board_sync_service = BoardSyncService.new(context.card_context)

# ============= EVT_* HANDLERS (ClientAPI signals) =============

func _on_evt_start_game(game_id: String, players: Array, spectator: bool) -> void:
    # 1. Mettre à jour Global + context
    Global.current_game_id = String(game_id)
    Global.players_in_game = players
    Global.is_spectator = bool(spectator)
    Global.result.clear()

    context.current_game_id = Global.current_game_id
    context.is_spectator = Global.is_spectator
    context.players_in_game = Global.players_in_game.duplicate()
    context.result = {}

    # 2. Reset des flags de session
    context.is_changing_scene = false
    context.game_end_prompted = false
    context.leave_sent = false
    context.opponent_disconnected = false
    context.network_disconnected = false
    context.disconnect_prompt_seq += 1

    # 3. Reset board : vider tous les slots connus
    if context.card_context != null and context.card_context.slots_by_id != null:
        for slot in context.card_context.slots_by_id.values():
            if slot != null and slot.has_method("clear_slot"):
                slot.clear_slot()

    # 4. Réinitialiser la file d'événements
    context.slots_ready = true
    context.pending_events.clear()

    # 5. Sync des flags sur game_node (Game.gd lit encore ses propres vars)
    if context.game_node != null:
        context.game_node.slots_ready = true
        context.game_node.pending_events.clear()
        context.game_node._is_changing_scene = false
        context.game_node._game_end_prompted = false
        context.game_node._leave_sent = false
        context.game_node._opponent_disconnected = false
        context.game_node._disconnect_prompt_seq += 1

    PopupUi.hide_and_reset()

    # 6. Demander le snapshot de la nouvelle partie via ClientAPI
    if Global.current_game_id != "":
        if Global.is_spectator:
            ClientAPI.spectate_game(Global.current_game_id)
        else:
            ClientAPI.join_game(Global.current_game_id)

func _on_evt_state_snapshot(data: Dictionary) -> void:
    # Clear all slots first
    if context.card_context != null and context.card_context.slots_by_id != null:
        for slot in context.card_context.slots_by_id.values():
            if slot != null and slot.has_method("clear_slot"):
                slot.clear_slot()

    # Sync table slots
    if _board_sync_service != null:
        var table_node: Node = null
        if context.game_node != null:
            table_node = context.game_node.get_node_or_null("Board/Table")
        if table_node != null:
            var table_slots_val = data.get("table", [])
            var table_slots: Array = table_slots_val if table_slots_val is Array else []
            _board_sync_service.sync_table_slots(
                table_node,
                table_slots,
                preload("res://Scenes/Slot.tscn"),
                100,
                Vector2.ZERO
            )

    # Reset deck counts
    if context.game_node != null and context.game_node.has_method("_reset_deck_counts"):
        context.game_node._reset_deck_counts()

    # Sync slots & cards — cast défensif pour éviter l'Invalid cast
    var slots_raw = data.get("slots", null)
    var slots_dict: Dictionary = slots_raw if slots_raw is Dictionary else {}

    var counts_raw = data.get("slot_counts", null)
    var slot_counts_dict: Dictionary = counts_raw if counts_raw is Dictionary else {}
    if _board_sync_service != null:
        for slot_id in slots_dict.keys():
            var card_datas = slots_dict.get(slot_id, null)
            var card_datas_array: Array = card_datas if card_datas is Array else []
            var count_for_slot: int = card_datas_array.size()
            if slot_counts_dict.has(slot_id):
                count_for_slot = maxi(0, int(slot_counts_dict.get(slot_id, count_for_slot)))
            _board_sync_service.apply_slot_state(slot_id, card_datas_array, count_for_slot, false)
            if context.game_node != null and "_deck_count_state" in context.game_node:
                var deck_count_state = context.game_node._deck_count_state
                DeckCountUtil.update_from_slot(deck_count_state, slot_id, count_for_slot)

    # Turn data
    var turn_raw = data.get("turn", null)
    if turn_raw is Dictionary and not (turn_raw as Dictionary).is_empty():
        _on_evt_turn_update(turn_raw as Dictionary)

func _on_evt_table_sync(slots: Array) -> void:
    if _board_sync_service == null:
        return
    var table_node = context.game_node.get_node_or_null("Board/Table") if context.game_node else null
    if table_node == null:
        return
    _board_sync_service.sync_table_slots(
        table_node,
        slots,
        preload("res://Scenes/Slot.tscn"),
        GameLayoutConfig.TABLE_SPACING,
        GameLayoutConfig.START_POS
    )

func _on_evt_slot_state(slot_id: String, cards: Array, count: int) -> void:
    slot_id = SlotIdHelper.normalize_slot_id(String(slot_id))
    if slot_id == "":
        return
    var count_for_slot := maxi(0, int(count))
    if _board_sync_service != null:
        _board_sync_service.apply_slot_state(slot_id, cards, count_for_slot, true)
        if context.game_node != null and "_deck_count_state" in context.game_node:
            var deck_count_state = context.game_node._deck_count_state
            DeckCountUtil.update_from_slot(deck_count_state, slot_id, count_for_slot)

func _on_evt_game_end(data: Dictionary) -> void:
    GameSession.result = data.get("result", {})
    if context.game_node and context.game_node.has_method("_on_game_end"):
        context.game_node._on_game_end(data)

func _on_evt_turn_update(data: Dictionary) -> void:
    if context.ui_manager and context.ui_manager.has_method("set_turn_timer"):
        context.ui_manager.set_turn_timer(
            data,
            Callable(ClientAPI, "sync_server_clock"),
            GameSession.is_spectator,
            String(Global.username)
        )

func _on_evt_game_message(message_code: String, params: Dictionary) -> void:
    _show_game_feedback({
        "message_code": message_code,
        "message_params": params,
    })

func _on_evt_opponent_disconnected(game_id: String, username: String) -> void:
    context.opponent_disconnected = true
    if context.game_node and context.game_node.has_method("_on_opponent_disconnected"):
        context.game_node._on_opponent_disconnected({
            "game_id": game_id,
            "username": username,
        })

func _on_evt_opponent_rejoined(game_id: String, username: String) -> void:
    context.opponent_disconnected = false
    if context.game_node and context.game_node.has_method("_on_opponent_rejoined"):
        context.game_node._on_opponent_rejoined({
            "game_id": game_id,
            "username": username,
        })

func _on_evt_invite_received(from_user: String, invite_context: String, source_game_id: String) -> void:
    var from_user_clean := String(from_user)
    if from_user_clean == "":
        return
    PopupRouter.show_invite_received(
        from_user_clean,
        String(invite_context).strip_edges(),
        String(source_game_id).strip_edges()
    )

func _on_evt_invite_response(data: Dictionary) -> void:
    PopupRouter.show_invite_response(data)

func _on_evt_invite_cancelled(data: Dictionary) -> void:
    PopupRouter.show_invite_cancelled(data)

func _on_evt_rematch_declined(data: Dictionary) -> void:
    PopupRouter.show_rematch_declined(data)

# ============= MOVE RESPONSES (RULE_*) =============

func _on_move_ok(response_data: Dictionary) -> void:
    var card_id := String(response_data.get("card_id", ""))
    if card_id != "" and context.card_context != null:
        var card = context.card_context.cards.get(card_id)
        if card and card.has_method("_reset_move_pending"):
            card._reset_move_pending()

    _show_game_feedback({"message_code": GameMessage.RULE_OK})

    if context.game_node and context.game_node.has_method("_on_move_success"):
        context.game_node._on_move_success(response_data)

func _on_move_failed(error: Dictionary) -> void:
    var details_val = error.get("details", {})
    var details: Dictionary = details_val if details_val is Dictionary else {}

    var card_id := String(details.get("card_id", ""))
    if card_id != "" and context.card_context != null:
        var card = context.card_context.cards.get(card_id)
        if card and card.has_method("_reset_move_pending"):
            card._reset_move_pending()

    _show_game_feedback(_normalize_move_error(error))

    if details.has("card_id") and details.has("from_slot_id"):
        _rollback_invalid_move({
            "card_id": String(details.get("card_id", "")),
            "from_slot_id": String(details.get("from_slot_id", "")),
        })

# ============= INVITE RESPONSES =============

func _on_invite_sent() -> void:
    PopupRouter.show_info(Protocol.POPUP_INVITE_SENT)

func _on_invite_send_failed(error: Dictionary) -> void:
    PopupRouter.show_error(error, Protocol.POPUP_UI_ACTION_IMPOSSIBLE)

# ============= LOGIN RESPONSE =============

func _on_login_ok(_username: String, _status: String) -> void:
    if String(Global.current_game_id) != "":
        _request_game_sync()
    if _waiting_for_reauth:
        _waiting_for_reauth = false
        PopupRouter.show_info(Protocol.POPUP_PLAYER_RECONNECTED)

# ============= HELPERS =============

func _rollback_invalid_move(move_data: Dictionary) -> void:
    var card_id := String(move_data.get("card_id", ""))
    var from_slot_id := String(move_data.get("from_slot_id", ""))
    if card_id == "" or from_slot_id == "":
        return
    if context.card_context == null:
        return
    var card = context.card_context.cards.get(card_id)
    var from_slot = context.card_context.slots_by_id.get(from_slot_id)
    if card != null and from_slot != null:
        from_slot.snap_card(card, false)

func _normalize_move_error(error: Dictionary) -> Dictionary:
    """Retourne un dict RULE_* prêt pour _show_game_feedback, ou fallback RULE_MOVE_DENIED."""
    var message_code := String(error.get("message_code", "")).strip_edges()
    var text := String(error.get("text", "")).strip_edges()
    var message_params := _merge_error_message_params(error)

    var normalized := GameMessage.normalize_rule_message({
        "message_code": message_code,
        "text": text,
        "message_params": message_params,
    })
    if not normalized.is_empty():
        return normalized

    return GameMessage.normalize_rule_message({
        "message_code": GameMessage.RULE_MOVE_DENIED,
        "message_params": message_params,
    })

func _merge_error_message_params(error: Dictionary) -> Dictionary:
    """Source unique : fusionne message_params de l'enveloppe et des details."""
    var details_val: Variant = error.get("details", {})
    var details: Dictionary = details_val if details_val is Dictionary else {}

    var top_params_val: Variant = error.get("message_params", {})
    var top_params: Dictionary = top_params_val if top_params_val is Dictionary else {}

    var details_params_val: Variant = details.get("message_params", {})
    var details_params: Dictionary = details_params_val if details_params_val is Dictionary else {}

    var out: Dictionary = {}
    for key in details_params.keys():
        out[key] = details_params[key]
    for key in top_params.keys(): # top-level écrase details
        out[key] = top_params[key]
    return out

func _show_game_feedback(message_data: Dictionary) -> void:
    """Route vers GameUIManager — seuls les codes RULE_* sont affichés (filtre dans GameMessage)."""
    if context.ui_manager and context.ui_manager.has_method("show_game_feedback"):
        context.ui_manager.show_game_feedback(message_data)

func _request_game_sync() -> void:
    var game_id: String = String(Global.current_game_id)
    if game_id == "":
        return
    if bool(Global.is_spectator):
        ClientAPI.spectate_game(game_id)
    else:
        ClientAPI.join_game(game_id)

# ============= CONNEXION =============

func on_connection_lost() -> void:
    context.network_disconnected = true
    _waiting_for_reauth = false
    PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_PLAYER_DISCONNECTED)

func on_connection_restored() -> void:
    if not context.network_disconnected:
        return
    context.network_disconnected = false
    _waiting_for_reauth = true

func on_reconnect_failed() -> void:
    if not context.network_disconnected:
        return
    _waiting_for_reauth = false
    PopupUi.show_code(
        PopupUi.MODE_INFO,
        Protocol.POPUP_PLAYER_RECONNECT_FAIL,
        {}, {},
        {"ok_action_id": "network_retry", "ok_label_key": "UI_LABEL_RETRY"}
    )

func on_server_closed(_server_reason: String, _close_code: int, _raw_reason: String) -> void:
    context.network_disconnected = false
    PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_TECH_INTERNAL_ERROR)

# ============= FIN DE PARTIE =============

func _ack_end_and_go_lobby() -> void:
    var gid: String = String(GameSession.current_game_id)
    if gid != "":
        await ClientAPI.ack_game_end(gid)
    GameSession.current_game_id = ""
    GameSession.players_in_game = []
    GameSession.is_spectator = false
    GameSession.result = {}
    if context.game_node and context.game_node.has_method("_go_to_lobby_safe"):
        context.game_node._go_to_lobby_safe()

func _ack_end_invite_rematch_in_game() -> void:
    var gid: String = String(Global.current_game_id)
    var source_game_id := gid
    var opponent_name := _resolve_rematch_target_username()

    if gid != "":
        var ack_res := await ClientAPI.ack_game_end(gid, "rematch")
        if not bool(ack_res.get("ok", false)):
            var err_val = ack_res.get("error", {})
            var err: Dictionary = err_val if err_val is Dictionary else {}
            PopupRouter.show_error(err, Protocol.POPUP_UI_ACTION_IMPOSSIBLE)
            return

    if opponent_name == "":
        PopupRouter.show_info(Protocol.POPUP_INVITE_FAILED)
        return

    Global.current_game_id = ""
    Global.players_in_game = []
    Global.is_spectator = false
    Global.result = {}

    ClientAPI.send_invite(opponent_name, "rematch", source_game_id)

func _resolve_rematch_target_username() -> String:
    var self_name := String(Global.username).strip_edges()
    for player in Global.players_in_game:
        if player is String:
            var name := String(player).strip_edges()
            if name != "" and name != self_name:
                return name
        elif player is Dictionary:
            var name := String((player as Dictionary).get("username", "")).strip_edges()
            if name != "" and name != self_name:
                return name
    return ""

# ============= JOIN GAME OK (stub) =============

func _on_join_game_ok(_data: Dictionary) -> void:
    # Pour l'instant, aucune logique spécifique côté client ici.
    pass
