# Client/game/managers/GameStateManager.gd
extends RefCounted
class_name GameStateManager

const Protocol = preload("res://Client/net/Protocol.gd")
const GameMessage = preload("res://Client/game/helpers/GameMessage.gd")

# ============= PROPERTIES =============
var context: GameContext = null
var _card_sync_service: CardSyncService = null
var _table_sync_service: TableSyncService = null
var _waiting_for_reauth := false

# ============= LIFECYCLE =============
func _init(game_context: GameContext) -> void:
	context = game_context
	if context != null and context.card_context != null:
		_card_sync_service = CardSyncService.new(context.card_context)
		_table_sync_service = TableSyncService.new(context)

# ============= EVENT HANDLING =============
func handle_event(type: String, data: Dictionary) -> void:
	"""Main event handler - CLEAN SEPARATION:
	
	- RULE_* codes → show_game_message → GameUIManager → GameMessage panel
	- POPUP_* codes → opponent_disconnected / game_end / etc → Game.gd handlers → WindowPopup
	- NO generic UI handler - each event type knows how to display its own UI
	"""
	if context == null:
		return
	
	if not context.slots_ready:
		context.pending_events.append({"type": type, "data": data})
		return

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
			_handle_turn_update(data)
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
		"rematch_declined":
			_handle_rematch_declined(data)
		_:
			pass

func on_response(rid: String, type: String, ok: bool, _data: Dictionary, error: Dictionary) -> void:
	"""Handle network responses"""
	if context == null:
		return

	if type == "login":
		if ok and String(Global.current_game_id) != "":
			# Reconnected successfully
			pass
		if _waiting_for_reauth:
			_waiting_for_reauth = false
			if ok:
				PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_PLAYER_RECONNECTED)
			else:
				PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_PLAYER_RECONNECT_FAIL)
		return

	if type == "move_request":
		_handle_move_response(ok, _data, error)
		return

# ============= MOVE HANDLING =============
func _handle_move_response(ok: bool, response_data: Dictionary, error: Dictionary) -> void:
	"""Handle move_request response from server"""
	var card_id = response_data.get("card_id", "")
	
	# Re-enable dragging on card
	if card_id != "":
		var card = context.card_context.cards.get(card_id)
		if card and card.has_method("_reset_move_pending"):
			card._reset_move_pending()

	if ok:
		_show_game_feedback({"message_code": GameMessage.RULE_OK})
		# Emit event for successful move
		if context.game_node and context.game_node.has_method("_on_move_success"):
			context.game_node._on_move_success(response_data)
	else:
		# Handle move error
		var error_ui = _normalize_move_error(error)
		_show_game_feedback(error_ui)
		
		# Snap card back to origin slot if details available
		var details_val = error.get("details", {})
		var details: Dictionary = details_val if details_val is Dictionary else {}
		if details.has("card_id") and details.has("from_slot_id"):
			_rollback_invalid_move({
				"card_id": String(details.get("card_id", "")),
				"from_slot_id": String(details.get("from_slot_id", ""))
			})

# ============= EVENT HANDLERS =============
func _handle_start_game(data: Dictionary) -> void:
	"""Handle game start event"""
	context.current_game_id = String(data.get("game_id", ""))
	context.is_spectator = bool(data.get("is_spectator", false))
	# Delegate to game node for UI updates
	if context.game_node and context.game_node.has_method("_on_start_game"):
		context.game_node._on_start_game(data)

func _handle_table_sync(data: Dictionary) -> void:
	"""Handle table slots synchronization"""
	# Use TableSyncService to sync table slots
	if _table_sync_service == null:
		return
	
	# Extract table data from payload
	var table_node = context.game_node.get_node_or_null("Board/Table") if context.game_node else null
	if table_node == null:
		return
	# Call service to sync
	var active_slots = data.get("slots", [])
	var allowed_slots = data.get("allowed_slots", {})
	_table_sync_service.sync_table_slots(
		table_node,
		preload("res://Client/Scenes/Slot.tscn"),
		allowed_slots,
		active_slots,
		100,
		Vector2.ZERO
	)

func _handle_slot_state(data: Dictionary) -> void:
	"""Handle individual slot state update"""
	var slot_id := SlotIdHelper.normalize_slot_id(String(data.get("slot_id", "")))
	if slot_id == "":
		return
	
	var arr: Array = data.get("cards", [])
	var count_for_slot := arr.size()
	if data.has("count"):
		count_for_slot = maxi(0, int(data.get("count", count_for_slot)))
	
	_apply_slot_cards_update(slot_id, arr, count_for_slot, true)

# ============= SLOT & CARD SYNCHRONIZATION =============
func _apply_slot_cards_update(slot_id: String, card_array: Array, count_for_slot: int, animate: bool) -> void:
	"""Apply cards update to a slot with proper animation flow"""
	if context.card_context == null:
		return
	
	var slot = context.card_context.slots_by_id.get(slot_id)
	var normalized_count := maxi(0, count_for_slot)
	
	# Update server count
	if slot != null and slot.has_method("set_server_count"):
		slot.call("set_server_count", normalized_count)
	
	# Update deck count tracking UI
	if context.game_node:
		DeckCountUtil.update_from_slot(context.game_node._deck_count_state, slot_id, normalized_count)
	
	# BEGIN ANIMATION SEQUENCE
	if slot != null and slot.has_method("begin_server_sync"):
		slot.call("begin_server_sync", animate)
	
	# Sync all cards
	for i in range(card_array.size()):
		var payload = card_array[i]
		if payload is Dictionary:
			payload["_array_order"] = i
			if _card_sync_service != null:
				_card_sync_service.sync_card(payload)
	
	# END ANIMATION SEQUENCE - trigger positioning and animations
	if slot != null and slot.has_method("finalize_server_sync"):
		slot.call("finalize_server_sync")

func _handle_state_snapshot(data: Dictionary) -> void:
	"""Handle complete game state snapshot"""
	print("[GameStateManager] Processing state snapshot")
	
	# Clear all slots first
	if context.card_context and context.card_context.slots_by_id:
		for slot in context.card_context.slots_by_id.values():
			if slot and slot.has_method("clear_slot"):
				slot.clear_slot()
	
	# Sync table slots first
	if _table_sync_service != null:
		var table_node = context.game_node.get_node_or_null("Board/Table") if context.game_node else null
		if table_node != null:
			var table_slots = data.get("table", [])
			_table_sync_service.sync_table_slots(
				table_node,
				preload("res://Client/Scenes/Slot.tscn"),
				{},
				table_slots,
				100,
				Vector2.ZERO
			)
	
	# Reset deck counts
	if context.game_node and context.game_node.has_method("_reset_deck_counts"):
		context.game_node._reset_deck_counts()
	
	# Sync player slots and cards using proper animation flow
	var slots_dict: Dictionary = data.get("slots", {})
	var slot_counts_dict: Dictionary = data.get("slot_counts", {})
	print("[GameStateManager] Snapshot has %d slots" % slots_dict.size())
	
	if _card_sync_service != null:
		for slot_id in slots_dict.keys():
			var card_ids_array: Array = slots_dict.get(slot_id, [])
			var count_for_slot = slot_counts_dict.get(slot_id, card_ids_array.size())
			
			_apply_slot_cards_update(slot_id, card_ids_array, count_for_slot, false)
	
	# Handle turn data from snapshot (timebar initialization)
	var turn_data = data.get("turn", {})
	if not turn_data.is_empty():
		_handle_turn_update(turn_data)

func _handle_game_end(data: Dictionary) -> void:
	"""Handle game end event"""
	context.result = data.get("result", {})
	if context.game_node and context.game_node.has_method("_on_game_end"):
		context.game_node._on_game_end(data)

func _handle_turn_update(data: Dictionary) -> void:
	"""Handle turn update"""
	if context.ui_manager and context.ui_manager.has_method("set_turn_timer"):
		context.ui_manager.set_turn_timer(
			data,
			Callable(NetworkManager, "sync_server_clock"),
			context.is_spectator,
			String(Global.username)
		)

func _handle_opponent_disconnected(data: Dictionary) -> void:
	"""Handle opponent disconnection"""
	context.opponent_disconnected = true
	if context.game_node and context.game_node.has_method("_on_opponent_disconnected"):
		context.game_node._on_opponent_disconnected(data)

func _handle_opponent_rejoined(data: Dictionary) -> void:
	"""Handle opponent rejoin"""
	context.opponent_disconnected = false
	if context.game_node and context.game_node.has_method("_on_opponent_rejoined"):
		context.game_node._on_opponent_rejoined(data)

func _handle_invite_request(data: Dictionary) -> void:
	"""Handle rematch invite request"""
	if context.game_node and context.game_node.has_method("_on_invite_request"):
		context.game_node._on_invite_request(data)

func _handle_invite_response(data: Dictionary) -> void:
	"""Handle rematch invite response"""
	if context.game_node and context.game_node.has_method("_on_invite_response"):
		context.game_node._on_invite_response(data)

func _handle_invite_cancelled(data: Dictionary) -> void:
	"""Handle invite cancellation"""
	if context.game_node and context.game_node.has_method("_on_invite_cancelled"):
		context.game_node._on_invite_cancelled(data)

func _handle_rematch_declined(data: Dictionary) -> void:
	"""Handle rematch decline"""
	if context.game_node and context.game_node.has_method("_on_rematch_declined"):
		context.game_node._on_rematch_declined(data)

# ============= HELPERS =============
func _rollback_invalid_move(move_data: Dictionary) -> void:
	"""Snap card back to origin slot after failed move"""
	var card_id = String(move_data.get("card_id", ""))
	var from_slot_id = String(move_data.get("from_slot_id", ""))
	
	if card_id == "" or from_slot_id == "":
		return
	
	var card = context.card_context.cards.get(card_id)
	var from_slot = context.card_context.slots_by_id.get(from_slot_id)
	
	if card != null and from_slot != null:
		from_slot.snap_card(card, false)

func _normalize_move_error(error: Dictionary) -> Dictionary:
	"""Normalize move error into UI message"""
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
	"""Merge error message parameters from details and top-level"""
	var details_val = error.get("details", {})
	var details: Dictionary = details_val if details_val is Dictionary else {}
	var top_params_val = error.get("message_params", {})
	var top_params: Dictionary = top_params_val if top_params_val is Dictionary else {}
	var details_params_val = details.get("message_params", {})
	var details_params: Dictionary = details_params_val if details_params_val is Dictionary else {}

	var out: Dictionary = {}
	for key in details_params.keys():
		out[key] = details_params[key]
	for key in top_params.keys():
		out[key] = top_params[key]
	return out

func _show_game_feedback(message_data: Dictionary) -> void:
	"""Show feedback message to player"""
	if context.ui_manager and context.ui_manager.has_method("show_game_feedback"):
		context.ui_manager.show_game_feedback(message_data)

# ============= CONNECTION LIFECYCLE =============
func on_connection_lost() -> void:
	"""Handle network connection loss"""
	context.network_disconnected = true
	_waiting_for_reauth = false
	PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_PLAYER_DISCONNECTED)

func on_connection_restored() -> void:
	"""Handle network connection restoration"""
	if not context.network_disconnected:
		return
	context.network_disconnected = false
	_waiting_for_reauth = true
	# Don't show popup yet, wait for authentication

func on_reconnect_failed() -> void:
	"""Handle failed reconnection attempt"""
	if not context.network_disconnected:
		return
	_waiting_for_reauth = false
	PopupUi.show_code(
		PopupUi.MODE_INFO,
		Protocol.POPUP_PLAYER_RECONNECT_FAIL,
		{},
		{},
		{"ok_action_id": "network_retry", "ok_label_key": "UI_LABEL_RETRY"}
	)

func on_server_closed(_server_reason: String, _close_code: int, _raw_reason: String) -> void:
	"""Handle server closure"""
	context.network_disconnected = false
	PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_TECH_INTERNAL_ERROR)

# ============= GAME END HANDLERS =============
func _ack_end_and_go_lobby() -> void:
	"""Acknowledge game end and return to lobby"""
	var gid := String(Global.current_game_id)
	if gid != "":
		await NetworkManager.request_async("ack_game_end", {"game_id": gid}, 6.0)
	
	Global.current_game_id = ""
	Global.players_in_game = []
	Global.is_spectator = false
	Global.result = {}
	
	if context.game_node and context.game_node.has_method("_go_to_lobby_safe"):
		await context.game_node._go_to_lobby_safe()

func _ack_end_invite_rematch_in_game() -> void:
	"""Acknowledge game end and invite for rematch"""
	var gid := String(Global.current_game_id)
	var source_game_id := gid
	var opponent_name := _resolve_rematch_target_username()
	
	if gid != "":
		var ack_res := await NetworkManager.request_async(
			"ack_game_end",
			{
				"game_id": gid,
				"intent": "rematch",
			},
			6.0
		)
		if not bool(ack_res.get("ok", false)):
			var err_val = ack_res.get("error", {})
			var err: Dictionary = err_val if err_val is Dictionary else {}
			PopupUi.show_normalized(PopupUi.MODE_INFO, PopupMessage.normalize_popup_error(err, Protocol.POPUP_UI_ACTION_IMPOSSIBLE))
			return
	
	if opponent_name == "":
		PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_INVITE_FAILED)
		return
	
	Global.current_game_id = ""
	Global.players_in_game = []
	Global.is_spectator = false
	Global.result = {}
	
	var invite_payload := {"to": opponent_name}
	if source_game_id != "":
		invite_payload["context"] = "rematch"
		invite_payload["source_game_id"] = source_game_id
	NetworkManager.request("invite", invite_payload)

func _resolve_rematch_target_username() -> String:
	"""Find the opponent's username for rematch invite"""
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
