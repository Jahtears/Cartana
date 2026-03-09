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
#             → _handle_*() → context.game_node._on_*()
#             → Game.gd → PopupUi.*
#             → WindowPopup
#
#   Réponses réseau :
#     move_request  → RULE_*  → _show_game_feedback()
#     invite        → POPUP_* → PopupUi direct (pas de passage par game_node car c'est une réponse, pas un événement)
#     login         → POPUP_* → PopupUi direct (reconnexion)

extends RefCounted
class_name GameStateManager

const Protocol    = preload("res://Client/net/Protocol.gd")

# ============= CONSTANTS =============
const REQ_INVITE := "invite"

# ============= PROPERTIES =============
var context: GameContext             = null
var _card_sync_service: CardSyncService  = null
var _table_sync_service: TableSyncService = null
var _waiting_for_reauth := false

# ============= LIFECYCLE =============
func _init(game_context: GameContext) -> void:
	context = game_context
	if context != null and context.card_context != null:
		_card_sync_service  = CardSyncService.new(context.card_context)
		_table_sync_service = TableSyncService.new(context)

# ============= EVENT ROUTING =============
func handle_event(type: String, data: Dictionary) -> void:
	if context == null:
		return

	if not context.slots_ready:
		context.pending_events.append({"type": type, "data": data})
		return

	match type:
		# ── Jeu ──────────────────────────────────────
		"start_game":           _handle_start_game(data)
		"table_sync":           _handle_table_sync(data)
		"slot_state":           _handle_slot_state(data)
		"state_snapshot":       _handle_state_snapshot(data)
		"turn_update":          _handle_turn_update(data)
		"game_end":             _handle_game_end(data)
		# ── RULE_* → GameMessage label ───────────────
		"show_game_message":    _show_game_feedback(data)
		# ── POPUP_* → WindowPopup via game_node ──────
		"opponent_disconnected": _handle_opponent_disconnected(data)
		"opponent_rejoined":     _handle_opponent_rejoined(data)
		"invite_request":        _handle_invite_request(data)
		"invite_response":       _handle_invite_response(data)
		"invite_cancelled":      _handle_invite_cancelled(data)
		"rematch_declined":      _handle_rematch_declined(data)

# ============= RESPONSE ROUTING =============
func on_response(_rid: String, type: String, ok: bool, data: Dictionary, error: Dictionary) -> void:
	if context == null:
		return

	match type:
		# ── POPUP_* : reconnexion ────────────────────
		"login":
			if ok and String(Global.current_game_id) != "":
				_request_game_sync()
			if _waiting_for_reauth:
				_waiting_for_reauth = false
				var code := Protocol.POPUP_PLAYER_RECONNECTED if ok else Protocol.POPUP_PLAYER_RECONNECT_FAIL
				PopupUi.show_code(PopupUi.MODE_INFO, code)

		# ── POPUP_* : résultat d'invitation ──────────
		REQ_INVITE:
			if ok:
				PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_INVITE_SENT)
			else:
				PopupUi.show_normalized(
					PopupUi.MODE_INFO,
					PopupMessage.normalize_popup_error(error, Protocol.POPUP_INVITE_FAILED)
				)

		# ── RULE_* : résultat de mouvement ───────────
		"move_request":
			_handle_move_response(ok, data, error)

# ============= MOVE HANDLING (RULE_*) =============
func _handle_move_response(ok: bool, response_data: Dictionary, error: Dictionary) -> void:
	var card_id := String(response_data.get("card_id", ""))

	if card_id != "":
		var card = context.card_context.cards.get(card_id)
		if card and card.has_method("_reset_move_pending"):
			card._reset_move_pending()

	if ok:
		_show_game_feedback({"message_code": GameMessage.RULE_OK})
		if context.game_node and context.game_node.has_method("_on_move_success"):
			context.game_node._on_move_success(response_data)
	else:
		_show_game_feedback(_normalize_move_error(error))
		var details_val = error.get("details", {})
		var details: Dictionary = details_val if details_val is Dictionary else {}
		if details.has("card_id") and details.has("from_slot_id"):
			_rollback_invalid_move({
				"card_id":       String(details.get("card_id", "")),
				"from_slot_id":  String(details.get("from_slot_id", "")),
			})

# ===================================================================
# PATCH GameStateManager.gd — remplacer les deux méthodes suivantes
# ===================================================================

func _handle_start_game(data: Dictionary) -> void:
	"""Handle start_game : reset de l'état courant + resync pour la nouvelle partie.
	Cas couverts : première entrée en jeu ET rematch (on est déjà dans Game.gd)."""

	# 1. Mettre à jour Global + context
	Global.current_game_id  = String(data.get("game_id", ""))
	Global.players_in_game  = data.get("players", [])
	Global.is_spectator      = bool(data.get("spectator", false))
	Global.result.clear()

	context.current_game_id  = Global.current_game_id
	context.is_spectator      = Global.is_spectator
	context.players_in_game  = Global.players_in_game.duplicate()
	context.result            = {}

	# 2. Reset des flags de session
	context.is_changing_scene      = false
	context.game_end_prompted      = false
	context.leave_sent             = false
	context.opponent_disconnected  = false
	context.network_disconnected   = false
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
		context.game_node.slots_ready          = true
		context.game_node.pending_events.clear()
		context.game_node._is_changing_scene   = false
		context.game_node._game_end_prompted   = false
		context.game_node._leave_sent          = false
		context.game_node._opponent_disconnected = false
		context.game_node._disconnect_prompt_seq += 1

	PopupUi.hide_and_reset()

	# 6. Demander le snapshot de la nouvelle partie
	if Global.current_game_id != "":
		var req_type := Protocol.REQ_SPECTATE_GAME if Global.is_spectator else Protocol.REQ_JOIN_GAME
		NetworkManager.request(req_type, {"game_id": Global.current_game_id})


func _handle_state_snapshot(data: Dictionary) -> void:
	"""Handle complete game state snapshot"""

	# Clear all slots first
	if context.card_context != null and context.card_context.slots_by_id != null:
		for slot in context.card_context.slots_by_id.values():
			if slot != null and slot.has_method("clear_slot"):
				slot.clear_slot()

	# Sync table slots
	if _table_sync_service != null:
		var table_node: Node = null
		if context.game_node != null:
			table_node = context.game_node.get_node_or_null("Board/Table")
		if table_node != null:
			var table_slots_val = data.get("table", [])
			var table_slots: Array = table_slots_val if table_slots_val is Array else []
			_table_sync_service.sync_table_slots(
				table_node,
				preload("res://Client/Scenes/Slot.tscn"),
				{},
				table_slots,
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

	if _card_sync_service != null:
		for slot_id in slots_dict.keys():
			var card_ids_raw = slots_dict.get(slot_id, null)
			var card_ids_array: Array = card_ids_raw if card_ids_raw is Array else []
			var count_for_slot: int = card_ids_array.size()
			if slot_counts_dict.has(slot_id):
				count_for_slot = maxi(0, int(slot_counts_dict.get(slot_id, count_for_slot)))
			_apply_slot_cards_update(slot_id, card_ids_array, count_for_slot, false)

	# Turn data
	var turn_raw = data.get("turn", null)
	if turn_raw is Dictionary and not (turn_raw as Dictionary).is_empty():
		_handle_turn_update(turn_raw as Dictionary)

func _handle_table_sync(data: Dictionary) -> void:
	if _table_sync_service == null:
		return
	var table_node = context.game_node.get_node_or_null("Board/Table") if context.game_node else null
	if table_node == null:
		return
	_table_sync_service.sync_table_slots(
		table_node,
		preload("res://Client/Scenes/Slot.tscn"),
		data.get("allowed_slots", {}),
		data.get("slots", []),
		GameLayoutConfig.TABLE_SPACING,
		GameLayoutConfig.START_POS
	)

func _handle_slot_state(data: Dictionary) -> void:
	var slot_id := SlotIdHelper.normalize_slot_id(String(data.get("slot_id", "")))
	if slot_id == "":
		return
	var arr: Array = data.get("cards", [])
	var count_for_slot := arr.size()
	if data.has("count"):
		count_for_slot = maxi(0, int(data.get("count", count_for_slot)))
	_apply_slot_cards_update(slot_id, arr, count_for_slot, true)

func _handle_game_end(data: Dictionary) -> void:
	context.result = data.get("result", {})
	if context.game_node and context.game_node.has_method("_on_game_end"):
		context.game_node._on_game_end(data)

func _handle_turn_update(data: Dictionary) -> void:
	if context.ui_manager and context.ui_manager.has_method("set_turn_timer"):
		context.ui_manager.set_turn_timer(
			data,
			Callable(NetworkManager, "sync_server_clock"),
			context.is_spectator,
			String(Global.username)
		)

# ============= POPUP_* EVENT HANDLERS (→ game_node → PopupUi) =============
func _handle_opponent_disconnected(data: Dictionary) -> void:
	context.opponent_disconnected = true
	if context.game_node and context.game_node.has_method("_on_opponent_disconnected"):
		context.game_node._on_opponent_disconnected(data)

func _handle_opponent_rejoined(data: Dictionary) -> void:
	context.opponent_disconnected = false
	if context.game_node and context.game_node.has_method("_on_opponent_rejoined"):
		context.game_node._on_opponent_rejoined(data)

# Remplacer les 4 méthodes suivantes dans GameStateManager.gd

func _handle_invite_request(data: Dictionary) -> void:
	var from_user := String(data.get("from", ""))
	if from_user == "":
		return
	var popup_payload := {
		"flow": PopupMessage.popup_flow("INVITE_REQUEST", Protocol.POPUP_FLOW_INVITE_REQUEST),
		"from": from_user,
	}
	var ctx_str := String(data.get("context", "")).strip_edges()
	var source_game_id := String(data.get("source_game_id", "")).strip_edges()
	if ctx_str != "":
		popup_payload["context"] = ctx_str
	if source_game_id != "":
		popup_payload["source_game_id"] = source_game_id
	PopupUi.show_code(
		PopupUi.MODE_CONFIRM,
		Protocol.POPUP_INVITE_RECEIVED,
		{"from": from_user},
		popup_payload,
		{"yes_label_key": "UI_LABEL_ACCEPT", "no_label_key": "UI_LABEL_REFUSE"}
	)

func _handle_invite_response(data: Dictionary) -> void:
	var ui := PopupMessage.normalize_invite_response_ui(data)
	if String(ui.get("text", "")) != "":
		PopupUi.show_normalized(PopupUi.MODE_INFO, ui)

func _handle_invite_cancelled(data: Dictionary) -> void:
	var ui := PopupMessage.invite_cancelled_ui(data)
	if String(ui.get("text", "")).strip_edges() == "":
		return
	PopupUi.show_normalized(PopupUi.MODE_INFO, ui)

func _handle_rematch_declined(data: Dictionary) -> void:
	var rematch_ctx := String(data.get("context", "")).strip_edges().to_lower()
	if rematch_ctx != Protocol.REMATCH_CONTEXT:
		return
	var ui := PopupMessage.normalize_invite_response_ui(data)
	PopupUi.show_normalized(
		PopupUi.MODE_INFO,
		ui,
		{
			"context": rematch_ctx,
			"source_game_id": String(data.get("source_game_id", "")).strip_edges(),
		}
	)

# ============= SLOT & CARD SYNCHRONIZATION =============
func _apply_slot_cards_update(slot_id: String, card_array: Array, count_for_slot: int, animate: bool) -> void:
	if context.card_context == null:
		return

	var slot = context.card_context.slots_by_id.get(slot_id)
	var normalized_count := maxi(0, count_for_slot)

	if slot != null and slot.has_method("set_server_count"):
		slot.call("set_server_count", normalized_count)

	if context.game_node:
		DeckCountUtil.update_from_slot(context.game_node._deck_count_state, slot_id, normalized_count)

	if slot != null and slot.has_method("begin_server_sync"):
		slot.call("begin_server_sync", animate)

	for i in range(card_array.size()):
		var payload = card_array[i]
		if payload is Dictionary:
			payload["_array_order"] = i
			if _card_sync_service != null:
				_card_sync_service.sync_card(payload)

	if slot != null and slot.has_method("finalize_server_sync"):
		slot.call("finalize_server_sync")

# ============= HELPERS =============
func _rollback_invalid_move(move_data: Dictionary) -> void:
	var card_id      := String(move_data.get("card_id", ""))
	var from_slot_id := String(move_data.get("from_slot_id", ""))
	if card_id == "" or from_slot_id == "":
		return
	var card      = context.card_context.cards.get(card_id)
	var from_slot = context.card_context.slots_by_id.get(from_slot_id)
	if card != null and from_slot != null:
		from_slot.snap_card(card, false)

func _normalize_move_error(error: Dictionary) -> Dictionary:
	"""Retourne un dict RULE_* prêt pour _show_game_feedback, ou fallback RULE_MOVE_DENIED."""
	var message_code   := String(error.get("message_code", "")).strip_edges()
	var text           := String(error.get("text", "")).strip_edges()
	var message_params := _merge_error_message_params(error)

	var normalized := GameMessage.normalize_rule_message({
		"message_code":   message_code,
		"text":           text,
		"message_params": message_params,
	})
	if not normalized.is_empty():
		return normalized

	return GameMessage.normalize_rule_message({
		"message_code":   GameMessage.RULE_MOVE_DENIED,
		"message_params": message_params,
	})

func _merge_error_message_params(error: Dictionary) -> Dictionary:
	"""Source unique : fusionne message_params de l'enveloppe et des details."""
	var details_val :Variant= error.get("details", {})
	var details: Dictionary = details_val if details_val is Dictionary else {}

	var top_params_val :Variant= error.get("message_params", {})
	var top_params: Dictionary = top_params_val if top_params_val is Dictionary else {}

	var details_params_val :Variant= details.get("message_params", {})
	var details_params: Dictionary = details_params_val if details_params_val is Dictionary else {}

	var out: Dictionary = {}
	for key in details_params.keys():
		out[key] = details_params[key]
	for key in top_params.keys():       # top-level écrase details
		out[key] = top_params[key]
	return out

func _show_game_feedback(message_data: Dictionary) -> void:
	"""Route vers GameUIManager — seuls les codes RULE_* sont affichés (filtre dans GameMessage)."""
	if context.ui_manager and context.ui_manager.has_method("show_game_feedback"):
		context.ui_manager.show_game_feedback(message_data)

func _request_game_sync() -> void:
	var game_id := String(Global.current_game_id)
	if game_id == "":
		return
	var req_type := "spectate_game" if bool(Global.is_spectator) else "join_game"
	NetworkManager.request(req_type, {"game_id": game_id})

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
	var gid := String(Global.current_game_id)
	if gid != "":
		await NetworkManager.request_async("ack_game_end", {"game_id": gid}, 6.0)
	Global.current_game_id  = ""
	Global.players_in_game  = []
	Global.is_spectator     = false
	Global.result           = {}
	if context.game_node and context.game_node.has_method("_go_to_lobby_safe"):
		await context.game_node._go_to_lobby_safe()

func _ack_end_invite_rematch_in_game() -> void:
	var gid            := String(Global.current_game_id)
	var source_game_id := gid
	var opponent_name  := _resolve_rematch_target_username()

	if gid != "":
		var ack_res := await NetworkManager.request_async(
			"ack_game_end", {"game_id": gid, "intent": "rematch"}, 6.0
		)
		if not bool(ack_res.get("ok", false)):
			var err_val = ack_res.get("error", {})
			var err: Dictionary = err_val if err_val is Dictionary else {}
			PopupUi.show_normalized(
				PopupUi.MODE_INFO,
				PopupMessage.normalize_popup_error(err, Protocol.POPUP_UI_ACTION_IMPOSSIBLE)
			)
			return

	if opponent_name == "":
		PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_INVITE_FAILED)
		return

	Global.current_game_id = ""
	Global.players_in_game = []
	Global.is_spectator    = false
	Global.result          = {}

	var invite_payload := {"to": opponent_name}
	if source_game_id != "":
		invite_payload["context"]        = "rematch"
		invite_payload["source_game_id"] = source_game_id
	NetworkManager.request(REQ_INVITE, invite_payload)

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
