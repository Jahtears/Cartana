# GameResponseHandler.gd - Handles server responses to client requests
extends RefCounted
class_name GameResponseHandler

const Protocol = preload("res://Client/net/Protocol.gd")

# ============= RESPONSE HANDLERS =============

static func handle_response(rid: String, type: String, ok: bool, data: Dictionary, error: Dictionary, game_ref: Node) -> void:
	"""Main response handler - routes to appropriate sub-handler"""
	if type == "login":
		if ok and String(Global.current_game_id) != "":
			game_ref._request_game_sync()
		return

	if type == "invite":
		_handle_invite_response(ok, error)
		return

	if type != "move_request":
		return

	_handle_move_response(rid, data, ok, error, game_ref)


# ============= INVITE RESPONSE =============

static func _handle_invite_response(ok: bool, error: Dictionary) -> void:
	"""Handle response to invite request"""
	if ok:
		PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_INVITE_SENT)
	else:
		PopupUi.show_normalized(
			PopupUi.MODE_INFO,
			Protocol.normalize_popup_error(error, Protocol.POPUP_INVITE_FAILED)
		)


# ============= MOVE RESPONSE =============

static func _handle_move_response(rid: String, data: Dictionary, ok: bool, error: Dictionary, game_ref: Node) -> void:
	"""Handle move request response"""
	var card_id = data.get("card_id", "")
	if card_id != "":
		var card = game_ref.cards.get(card_id)
		if card and card.has_method("_reset_move_pending"):
			card._reset_move_pending()

	if ok:
		game_ref._show_game_feedback({
			"message_code": GameMessage.RULE_OK,
		})
	else:
		var ui := _normalize_move_error(error, GameMessage.RULE_MOVE_DENIED)
		var details_val = error.get("details", {})
		var details: Dictionary = details_val if details_val is Dictionary else {}
		game_ref._show_game_feedback(ui)

		if details.has("card_id") and details.has("from_slot_id"):
			game_ref._on_invalid_move({
				"card_id": String(details.get("card_id", "")),
				"from_slot_id": String(details.get("from_slot_id", ""))
			})


# ============= ERROR NORMALIZATION =============

static func _normalize_move_error(error: Dictionary, fallback_message_code: String) -> Dictionary:
	"""Normalize move error for display"""
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


static func _merge_error_message_params(error: Dictionary) -> Dictionary:
	"""Merge all message params from error structure"""
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
