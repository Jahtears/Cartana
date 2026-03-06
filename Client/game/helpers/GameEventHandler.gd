# GameEventHandler.gd - Centralizes all server event handling
extends RefCounted
class_name GameEventHandler

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

# ============= EVENT HANDLERS =============

static func handle_start_game(data: Dictionary, game_ref: Node) -> void:
	"""Handle 'start_game' event from server"""
	Global.current_game_id = String(data.get("game_id", ""))
	Global.players_in_game = data.get("players", [])
	Global.is_spectator = bool(data.get("spectator", false))
	Global.result.clear()

	game_ref._reset_board_state()
	game_ref.slots_ready = true
	game_ref.pending_events.clear()
	game_ref._is_changing_scene = false
	game_ref._game_end_prompted = false
	game_ref._leave_sent = false
	game_ref._opponent_disconnected = false
	game_ref._network_disconnected = false
	game_ref._disconnect_prompt_seq += 1
	PopupUi.hide_and_reset()

	if Global.current_game_id != "":
		game_ref._request_game_sync()


static func handle_table_sync(data: Dictionary, game_ref: Node) -> void:
	"""Handle 'table_sync' event - synchronize table slots"""
	if game_ref.slots_ready:
		TableSyncHelper.sync_table_slots(
			game_ref.table_root,
			game_ref.slot_scene,
			game_ref.slots_by_id,
			game_ref.allowed_table_slots,
			data.get("slots", []),
			game_ref._table_spacing,
			game_ref.START_POS
		)
	else:
		game_ref.pending_events.append({"type": "table_sync", "data": data})


static func handle_slot_state(data: Dictionary, game_ref: Node) -> void:
	"""Handle 'slot_state' event - update individual slot"""
	if game_ref.slots_ready:
		_apply_slot_state_update(data, game_ref)
	else:
		game_ref.pending_events.append({"type": "slot_state", "data": data})


static func handle_state_snapshot(data: Dictionary, game_ref: Node) -> void:
	"""Handle 'state_snapshot' event - replace entire game state"""
	if game_ref.slots_ready:
		_apply_state_snapshot(data, game_ref)
	else:
		game_ref.pending_events.append({"type": "state_snapshot", "data": data})


static func handle_game_end(data: Dictionary, game_ref: Node) -> void:
	"""Handle 'game_end' event"""
	Global.result = data.duplicate()
	var merged := data.duplicate(true)
	merged["game_id"] = String(merged.get("game_id", String(Global.current_game_id)))
	game_ref._on_game_end(merged)


static func handle_invite_request(data: Dictionary) -> void:
	"""Handle incoming invite request"""
	var from_user := String(data.get("from", ""))
	if from_user != "":
		var popup_payload := {
			"flow": Protocol.popup_flow("INVITE_REQUEST", FLOW_INVITE_REQUEST),
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


static func handle_invite_response(data: Dictionary) -> void:
	"""Handle response to our invite"""
	var ui := Protocol.normalize_invite_response_ui(data)
	if String(ui.get("text", "")) != "":
		PopupUi.show_normalized(PopupUi.MODE_INFO, ui)


static func handle_invite_cancelled(data: Dictionary) -> void:
	"""Handle cancelled invite"""
	var ui := Protocol.invite_cancelled_ui(data)
	if String(ui.get("text", "")).strip_edges() == "":
		return
	PopupUi.show_normalized(PopupUi.MODE_INFO, ui)


static func handle_rematch_declined(data: Dictionary) -> void:
	"""Handle rematch decline"""
	var context := String(data.get("context", "")).strip_edges().to_lower()
	if context != REMATCH_CONTEXT:
		return
	var ui := Protocol.normalize_invite_response_ui(data)
	PopupUi.show_normalized(
		PopupUi.MODE_INFO,
		ui,
		{
			"ok_action_id": "rematch_declined_leave",
			"context": context,
			"source_game_id": String(data.get("source_game_id", "")).strip_edges(),
		},
		{"ok_label_key": "UI_LABEL_BACK_LOBBY"}
	)


static func handle_opponent_disconnected(data: Dictionary, game_ref: Node) -> void:
	"""Handle opponent disconnect"""
	var who := String(data.get("username", ""))
	game_ref._opponent_disconnected = true
	PopupUi.show_code(PopupUi.MODE_PASSIVE, Protocol.POPUP_OPPONENT_DISCONNECTED, {"name": who})
	game_ref._schedule_disconnect_choice(who)


static func handle_opponent_rejoined(data: Dictionary, game_ref: Node) -> void:
	"""Handle opponent reconnection"""
	var who := String(data.get("username", ""))
	game_ref._opponent_disconnected = false
	game_ref._disconnect_prompt_seq += 1
	PopupUi.hide_and_reset()
	PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_OPPONENT_REJOINED, {"name": who})


# ============= PRIVATE HELPERS =============

static func _apply_slot_state_update(data: Dictionary, game_ref: Node) -> void:
	"""Apply slot_state update from server"""
	var slot_id := SlotIdHelper.normalize_slot_id(String(data.get("slot_id", "")))
	if slot_id == "":
		return

	var slot = game_ref._resolve_slot_for_update(slot_id, true)
	if slot == null and SlotIdHelper.is_table_slot_id(slot_id) and not game_ref.allowed_table_slots.has(slot_id):
		return

	var arr: Array = data.get("cards", [])
	var count_for_slot := arr.size()
	if data.has("count"):
		count_for_slot = maxi(0, int(data.get("count", count_for_slot)))

	game_ref._apply_slot_cards_update(slot_id, slot, arr, count_for_slot, true, true)


static func _apply_state_snapshot(data: Dictionary, game_ref: Node) -> void:
	"""Apply complete state snapshot from server"""
	# Clear all slots
	for s in game_ref.slots_by_id.values():
		if s and s.has_method("clear_slot"):
			s.clear_slot()
	DeckCountUtil.reset_counts(game_ref._deck_count_state)

	# Sync table
	TableSyncHelper.sync_table_slots(
		game_ref.table_root,
		game_ref.slot_scene,
		game_ref.slots_by_id,
		game_ref.allowed_table_slots,
		data.get("table", []),
		game_ref._table_spacing,
		game_ref.START_POS
	)

	# Apply slot cards
	var slots_dict: Dictionary = data.get("slots", {})
	var slot_counts_val = data.get("slot_counts", null)
	var slot_counts: Dictionary = slot_counts_val if slot_counts_val is Dictionary else {}

	for k in slots_dict.keys():
		var slot_id := SlotIdHelper.normalize_slot_id(String(k))
		var slot = game_ref._resolve_slot_for_update(slot_id, false)

		var arr: Array = slots_dict.get(k, [])
		var count_for_slot := arr.size()
		if slot_counts.has(k):
			count_for_slot = maxi(0, int(slot_counts.get(k, count_for_slot)))

		game_ref._apply_slot_cards_update(slot_id, slot, arr, count_for_slot, false, false)

	# Apply turn state
	var turn_val = data.get("turn", null)
	if turn_val is Dictionary:
		game_ref._set_turn_timer(turn_val as Dictionary)
	else:
		game_ref._set_turn_timer({})

	# Apply game result if present
	var result_val = data.get("result", null)
	if result_val is Dictionary and (result_val as Dictionary).size() > 0:
		var e := result_val as Dictionary
		var merged := {"game_id": String(Global.current_game_id)}
		for kk in e.keys():
			merged[kk] = e[kk]
		game_ref._on_game_end(merged)
