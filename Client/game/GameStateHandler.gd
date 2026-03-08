extends RefCounted
class_name GameStateHandler

const Protocol = preload("res://Client/net/Protocol.gd")

var game: Node = null
var _waiting_for_reauth := false

func setup(game_ref: Node) -> void:
	game = game_ref

func handle_event(type: String, data: Dictionary) -> void:
	if game == null:
		return
	if not game.slots_ready:
		game.pending_events.append({"type": type, "data": data})
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
				game.ui_manager.show_game_feedback(data)
		"game_end":
			_handle_game_end(data)
		"turn_update":
				game.ui_manager.set_turn_timer(data, Callable(NetworkManager, "sync_server_clock"), bool(Global.is_spectator), String(Global.username))
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

func on_response(rid: String, type: String, ok: bool, _data: Dictionary, error: Dictionary) -> void:
	if game == null:
		return
	# Move response handling logic here
	if type == "login":
		if ok and String(Global.current_game_id) != "":
			_request_game_sync()
		if _waiting_for_reauth:
			_waiting_for_reauth = false
			if ok:
				PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_PLAYER_RECONNECTED)
			else:
				PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_PLAYER_RECONNECT_FAIL)
		return
	if type == game.REQ_INVITE:
		if ok:
			PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_INVITE_SENT)
		else:
			PopupUi.show_normalized(PopupUi.MODE_INFO, PopupMessage.normalize_popup_error(error, Protocol.POPUP_INVITE_FAILED))
		return

	if type != "move_request":
		return

	var card_id = _data.get("card_id", "")
	if card_id != "":
		var card = game.cards.get(card_id)
		if card and card.has_method("_reset_move_pending"):
			card._reset_move_pending()

	if ok:
		game.ui_manager.show_game_feedback({"message_code": GameMessage.RULE_OK})
	else:
		var ui := _normalize_move_error(error, GameMessage.RULE_MOVE_DENIED)
		var details_val = error.get("details", {})
		var details: Dictionary = details_val if details_val is Dictionary else {}
		game.ui_manager.show_game_feedback(ui)

		if details.has("card_id") and details.has("from_slot_id"):
			_on_invalid_move({
				"card_id": String(details.get("card_id", "")),
				"from_slot_id": String(details.get("from_slot_id", ""))
			})

# ============= HANDLERS & HELPERS (migrated from Game.gd) =============

func _handle_invite_request(data: Dictionary) -> void:
	var from_user := String(data.get("from", ""))
	if from_user != "":
		var popup_payload := {
			"flow": PopupMessage.popup_flow("INVITE_REQUEST", game.FLOW_INVITE_REQUEST),
			"from": from_user
		}
		var context := String(data.get("context", "")).strip_edges()
		var source_game_id := String(data.get("source_game_id", "")).strip_edges()
		if context != "":
			popup_payload["context"] = context
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
	var context := String(data.get("context", "")).strip_edges().to_lower()
	if context != game.REMATCH_CONTEXT:
		return
	var ui := PopupMessage.normalize_invite_response_ui(data)
	PopupUi.show_normalized(
		PopupUi.MODE_INFO,
		ui,
		{"context": context, "source_game_id": String(data.get("source_game_id", "")).strip_edges()},
		{"ok_action_id": game.ACTION_REMATCH_DECLINED_LEAVE, "ok_label_key": "UI_LABEL_BACK_LOBBY"}
	)

func _handle_start_game(data: Dictionary) -> void:
	Global.current_game_id = String(data.get("game_id", ""))
	Global.players_in_game = data.get("players", [])
	Global.is_spectator = bool(data.get("spectator", false))
	Global.result.clear()

	_reset_board_state()
	game.slots_ready = true
	game.pending_events.clear()
	game._is_changing_scene = false
	game._game_end_prompted = false
	game._leave_sent = false
	game._opponent_disconnected = false
	game._network_disconnected = false
	game._disconnect_prompt_seq += 1
	PopupUi.hide_and_reset()

	if Global.current_game_id != "":
		_request_game_sync()

func _handle_table_sync(data: Dictionary) -> void:
	if game.slots_ready:
		TableSyncHelper.sync_table_slots(game.table_root, game.slot_scene, game.slots_by_id, game.allowed_table_slots, data.get("slots", []), game._table_spacing, GameLayoutConfig.START_POS)
	else:
		game.pending_events.append({"type": "table_sync", "data": data})

func _handle_slot_state(data: Dictionary) -> void:
	if game.slots_ready:
		_on_slot_state(data)
	else:
		game.pending_events.append({"type": "slot_state", "data": data})

func _handle_state_snapshot(data: Dictionary) -> void:
	if game.slots_ready:
		_apply_state_snapshot(data)
	else:
		game.pending_events.append({"type": "state_snapshot", "data": data})

func _handle_game_end(data: Dictionary) -> void:
	Global.result = data.duplicate()
	var merged := data.duplicate(true)
	merged["game_id"] = String(merged.get("game_id", String(Global.current_game_id)))
	_on_game_end(merged)

func _handle_opponent_disconnected(data: Dictionary) -> void:
	var who := String(data.get("username", ""))
	game._opponent_disconnected = true
	PopupUi.show_code(PopupUi.MODE_PASSIVE, Protocol.POPUP_OPPONENT_DISCONNECTED, {"name": who})
	game._schedule_disconnect_choice(who)

func _handle_opponent_rejoined(data: Dictionary) -> void:
	var who := String(data.get("username", ""))
	game._opponent_disconnected = false
	game._disconnect_prompt_seq += 1
	PopupUi.hide_and_reset()
	PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_OPPONENT_REJOINED, {"name": who})

func on_connection_lost() -> void:
	game._network_disconnected = true
	_waiting_for_reauth = false
	PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_PLAYER_DISCONNECTED)

func on_connection_restored() -> void:
	if not game._network_disconnected:
		return
	game._network_disconnected = false
	_waiting_for_reauth = true
	# Don't show popup yet, wait for authentication

func on_reconnect_failed() -> void:
	if not game._network_disconnected:
		return
	_waiting_for_reauth = false
	PopupUi.show_code(
		PopupUi.MODE_INFO,
		Protocol.POPUP_PLAYER_RECONNECT_FAIL,
		{},
		{},
		{"ok_action_id": game.ACTION_NETWORK_RETRY, "ok_label_key": "UI_LABEL_RETRY"}
	)

func on_server_closed(_server_reason: String, _close_code: int, _raw_reason: String) -> void:
	game._network_disconnected = false
	PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_TECH_INTERNAL_ERROR)

func _normalize_move_error(error: Dictionary, fallback_message_code: String) -> Dictionary:
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
		"message_code": fallback_message_code,
		"message_params": message_params,
	})

func _merge_error_message_params(error: Dictionary) -> Dictionary:
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

func _request_game_sync() -> void:
	var game_id := String(Global.current_game_id)
	if game_id == "":
		return

	if bool(Global.is_spectator):
		NetworkManager.request(game.REQ_SPECTATE_GAME, {"game_id": game_id})
	else:
		NetworkManager.request(game.REQ_JOIN_GAME, {"game_id": game_id})

func _resolve_slot_for_update(slot_id: String, require_allowed_table: bool) -> Variant:
	var slot :Variant= game.slots_by_id.get(slot_id)
	if slot == null and SlotIdHelper.is_table_slot_id(slot_id):
		if require_allowed_table and not game.allowed_table_slots.has(slot_id):
			return null
		slot = game.slots_by_id.get(slot_id)
	return slot

func _apply_slot_cards_update(slot_id: String, slot, arr: Array, count_for_slot: int, animate_on_finalize: bool, clear_slot_first: bool) -> void:
	if clear_slot_first and slot != null and slot.has_method("clear_slot"):
		slot.clear_slot()

	var normalized_count := maxi(0, count_for_slot)
	if slot != null and slot.has_method("set_server_count"):
		slot.call("set_server_count", normalized_count)
	DeckCountUtil.update_from_slot(game._deck_count_state, slot_id, normalized_count)
	if slot != null and slot.has_method("begin_server_sync"):
		slot.call("begin_server_sync", animate_on_finalize)

	for i in range(arr.size()):
		var payload = arr[i]
		if payload is Dictionary:
			payload["_array_order"] = i
			CardSyncHelper.apply_card_update(game._card_ctx, payload)

	if slot != null and slot.has_method("finalize_server_sync"):
		slot.call("finalize_server_sync")

func _apply_state_snapshot(data: Dictionary) -> void:
	for s in game.slots_by_id.values():
		if s and s.has_method("clear_slot"):
			s.clear_slot()
	DeckCountUtil.reset_counts(game._deck_count_state)

	TableSyncHelper.sync_table_slots(game.table_root, game.slot_scene, game.slots_by_id, game.allowed_table_slots, data.get("table", []), game._table_spacing, GameLayoutConfig.START_POS)

	var slots_dict: Dictionary = data.get("slots", {})
	var slot_counts_val = data.get("slot_counts", null)
	var slot_counts: Dictionary = slot_counts_val if slot_counts_val is Dictionary else {}
	for k in slots_dict.keys():
		var slot_id := SlotIdHelper.normalize_slot_id(String(k))
		var slot = _resolve_slot_for_update(slot_id, false)

		var arr: Array = slots_dict.get(k, [])
		var count_for_slot := arr.size()
		if slot_counts.has(k):
			count_for_slot = maxi(0, int(slot_counts.get(k, count_for_slot)))
		_apply_slot_cards_update(slot_id, slot, arr, count_for_slot, false, false)

	var turn_val = data.get("turn", null)
	if turn_val is Dictionary:
		game._set_turn_timer(turn_val as Dictionary)
	else:
		game._set_turn_timer({})

	var result_val = data.get("result", null)
	if result_val is Dictionary and (result_val as Dictionary).size() > 0:
		var e := result_val as Dictionary
		var merged := {"game_id": String(Global.current_game_id)}
		for kk in e.keys():
			merged[kk] = e[kk]
		_on_game_end(merged)

func _on_game_end(data: Dictionary) -> void:
	if game._game_end_prompted:
		return
	game._game_end_prompted = true
	var popup_msg := PopupMessage.game_end_popup_message(data, String(Global.username), bool(Global.is_spectator))
	var rematch_allowed := bool(data.get("rematch_allowed", true))
	if game._opponent_disconnected:
		rematch_allowed = false
	if bool(Global.is_spectator) or not rematch_allowed:
		PopupUi.show_code(
			PopupUi.MODE_INFO,
			String(popup_msg.get("message_code", "")),
			popup_msg.get("message_params", {}) as Dictionary,
			{"game_id": String(Global.current_game_id)},
			{"ok_action_id": game.ACTION_GAME_END_LEAVE, "ok_label_key": "UI_LABEL_BACK_LOBBY"}
		)
		return

	PopupUi.show_code(
		PopupUi.MODE_CONFIRM,
		String(popup_msg.get("message_code", "")),
		popup_msg.get("message_params", {}) as Dictionary,
		{"game_id": String(Global.current_game_id)},
		{"yes_action_id": game.ACTION_GAME_END_LEAVE, "no_action_id": game.ACTION_GAME_END_REMATCH, "yes_label_key": "UI_LABEL_BACK_LOBBY", "no_label_key": "UI_LABEL_REMATCH"}
	)

func _ack_end_and_go_lobby() -> void:
	var gid := String(Global.current_game_id)
	if gid != "":
		await NetworkManager.request_async(game.REQ_ACK_GAME_END, {"game_id": gid}, 6.0)

	Global.current_game_id = ""
	Global.players_in_game = []
	Global.is_spectator = false
	Global.result = {}

	await game._go_to_lobby_safe()

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
			game.REQ_ACK_GAME_END,
			{
				"game_id": gid,
				"intent": game.ACK_INTENT_REMATCH,
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
	_reset_board_state()

	var invite_payload := {"to": opponent_name}
	if source_game_id != "":
		invite_payload["context"] = game.REMATCH_CONTEXT
		invite_payload["source_game_id"] = source_game_id
	NetworkManager.request(game.REQ_INVITE, invite_payload)

func _on_slot_state(data: Dictionary) -> void:
	var slot_id := SlotIdHelper.normalize_slot_id(String(data.get("slot_id", "")))
	if slot_id == "":
		return

	var slot = _resolve_slot_for_update(slot_id, true)
	if slot == null and SlotIdHelper.is_table_slot_id(slot_id) and not game.allowed_table_slots.has(slot_id):
		return

	var arr: Array = data.get("cards", [])
	var count_for_slot := arr.size()
	if data.has("count"):
		count_for_slot = maxi(0, int(data.get("count", count_for_slot)))
	_apply_slot_cards_update(slot_id, slot, arr, count_for_slot, true, true)

func _on_invalid_move(data: Dictionary) -> void:
	var card_id: String = String(data.get("card_id", ""))
	var from_slot_id: String = SlotIdHelper.normalize_slot_id(String(data.get("from_slot_id", "")))
	if card_id == "" or from_slot_id == "":
		return

	var card = CardSyncHelper.get_or_create_card(game._card_ctx, card_id)
	var slot = game.slots_by_id.get(from_slot_id)
	if slot:
		slot.snap_card(card, true)
		card.set_meta("last_slot_id", from_slot_id)

func _reset_board_state() -> void:
	for s in game.slots_by_id.values():
		if s and s.has_method("clear_slot"):
			s.clear_slot()
	DeckCountUtil.reset_counts(game._deck_count_state)

	TableSyncHelper.sync_table_slots(game.table_root, game.slot_scene, game.slots_by_id, game.allowed_table_slots, ["0:TABLE:1"], game._table_spacing, GameLayoutConfig.START_POS)

	for k in game.cards.keys():
		var c = game.cards[k]
		if is_instance_valid(c):
			c.queue_free()
	game.cards.clear()

	game.pending_events.clear()
	game.slots_ready = true
