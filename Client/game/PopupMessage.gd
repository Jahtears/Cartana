# PopupMessage.gd
# Extracted from Protocol.gd to handle all popup message normalization logic
extends RefCounted
class_name PopupMessage

const Protocol = preload("res://Client/net/Protocol.gd")

static func normalize_popup_message(payload: Dictionary) -> Dictionary:
	var params := _extract_message_params(payload)
	var message_code := _extract_message_code(payload)
	var text_override := _extract_text(payload)

	if not message_code.begins_with(Protocol.POPUP_PREFIX):
		if text_override != "":
			message_code = Protocol.POPUP_TECH_ERROR_GENERIC
		else:
			message_code = Protocol.DEFAULT_ERROR_FALLBACK

	var text := text_override
	if text == "" or text == message_code:
		text = popup_text(message_code, params)
	if text == "":
		text = popup_text(Protocol.POPUP_TECH_ERROR_GENERIC)

	var normalized := {
		"text": text,
		"message_code": message_code,
		"message_params": params,
	}
	if text_override != "" and text_override != message_code:
		normalized["text_override"] = text_override
	return normalized

static func normalize_popup_error(error: Dictionary, fallback_message := Protocol.DEFAULT_ERROR_FALLBACK) -> Dictionary:
	var top_params_val = error.get("message_params", {})
	var top_params: Dictionary = top_params_val if top_params_val is Dictionary else {}

	var message_code := String(error.get("message_code", "")).strip_edges()
	var text_override := String(error.get("text", "")).strip_edges()
	var fallback := String(fallback_message).strip_edges()

	if message_code == "":
		if fallback.begins_with(Protocol.POPUP_PREFIX):
			message_code = fallback
		else:
			message_code = Protocol.POPUP_TECH_ERROR_GENERIC
			if text_override == "":
				text_override = fallback

	if not message_code.begins_with(Protocol.POPUP_PREFIX):
		if text_override == "":
			text_override = message_code
		message_code = Protocol.POPUP_TECH_ERROR_GENERIC

	return normalize_popup_message({
		"message_code": message_code,
		"message_params": top_params,
		"text": text_override,
	})

static func popup_text(message_code: String, params: Dictionary = {}) -> String:
	return LanguageManager.popup_text(message_code, params)

static func popup_label(label_key: String) -> String:
	return LanguageManager.label(label_key, label_key)

static func popup_flow(key: String, fallback := "") -> String:
	return String(Protocol.POPUP_FLOW.get(key, fallback))

static func popup_action(key: String, fallback := "") -> String:
	return String(Protocol.POPUP_ACTION.get(key, fallback))

static func normalize_invite_response_ui(data: Dictionary) -> Dictionary:
	var ui_payload_val = data.get("ui", {})
	var ui_payload: Dictionary = ui_payload_val if ui_payload_val is Dictionary else {}
	return normalize_popup_message(ui_payload)

static func invite_cancelled_ui(data: Dictionary) -> Dictionary:
	var user_name := String(data.get("name", "")).strip_edges()
	if user_name == "":
		user_name = LanguageManager.ui_text("UI_GENERIC_USER", "User")

	return normalize_popup_message({
		"message_code": Protocol.POPUP_INVITE_CANCELLED,
		"message_params": {
			"name": user_name,
		},
	})

static func invite_action_request(action_id: String, payload: Dictionary) -> Dictionary:
	var flow := String(payload.get("flow", ""))
	if flow != Protocol.POPUP_FLOW_INVITE_REQUEST:
		return {}

	var from_user := String(payload.get("from", ""))
	if from_user == "":
		return {}

	var req := {}
	req["to"] = from_user
	var context := String(payload.get("context", "")).strip_edges()
	var source_game_id := String(payload.get("source_game_id", "")).strip_edges()
	if context != "":
		req["context"] = context
	if source_game_id != "":
		req["source_game_id"] = source_game_id

	if action_id == Protocol.POPUP_ACTION_CONFIRM_YES:
		req["accepted"] = true
		return req
	if action_id == Protocol.POPUP_ACTION_CONFIRM_NO:
		req["accepted"] = false
		return req
	return {}

static func game_end_popup_message(data: Dictionary, username: String, is_spectator: bool) -> Dictionary:
	var winner := _safe_text(data.get("winner", ""))
	var reason := _safe_text(data.get("reason", "")).to_lower()
	if reason == "":
		reason = Protocol.GAME_END_REASON_ABANDON

	if is_spectator:
		var spectator_code := _game_end_code_from_reason(reason)
		var spectator_params := {"name": winner if winner != "" else "-"}
		return {
			"message_code": spectator_code,
			"message_params": spectator_params,
		}

	if reason == Protocol.GAME_END_REASON_PILE_EMPTY:
		return {
			"message_code": Protocol.POPUP_GAME_END_DRAW,
			"message_params": {},
		}

	if winner == "":
		return {
			"message_code": Protocol.POPUP_GAME_END_DRAW,
			"message_params": {},
		}

	if winner == _safe_text(username):
		return {
			"message_code": Protocol.POPUP_GAME_END_VICTORY,
			"message_params": {},
		}

	return {
		"message_code": Protocol.POPUP_GAME_END_DEFEAT,
		"message_params": {},
	}

static func _game_end_code_from_reason(reason: String) -> String:
	match reason:
		Protocol.GAME_END_REASON_ABANDON:
			return Protocol.POPUP_GAME_END_ABANDON
		Protocol.GAME_END_REASON_DECK_EMPTY:
			return Protocol.POPUP_GAME_END_DECK_EMPTY
		Protocol.GAME_END_REASON_PILE_EMPTY:
			return Protocol.POPUP_GAME_END_PILE_EMPTY
		Protocol.GAME_END_REASON_TIMEOUT_STREAK:
			return Protocol.POPUP_GAME_END_TIMEOUT_STREAK
		_:
			return Protocol.POPUP_GAME_ENDED

static func _safe_text(value: Variant) -> String:
	if value == null:
		return ""
	return str(value).strip_edges()

static func _extract_message_params(payload: Dictionary) -> Dictionary:
	var params_val = payload.get("message_params", {})
	return params_val if params_val is Dictionary else {}

static func _extract_message_code(payload: Dictionary) -> String:
	return String(payload.get("message_code", "")).strip_edges()

static func _extract_text(payload: Dictionary) -> String:
	return String(payload.get("text", "")).strip_edges()
