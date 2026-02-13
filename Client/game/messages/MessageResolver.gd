extends RefCounted
class_name MessageResolver

const PopupMessages = preload("res://Client/game/messages/PopupMessages.gd")
const InlineMessages = preload("res://Client/game/messages/InlineMessages.gd")
const DEFAULT_ERROR_FALLBACK := "MSG_POPUP_UI_ACTION_IMPOSSIBLE"

const GAME_MESSAGE := {
	"TURN_START": "TURN_START",
	"MOVE_OK": "MOVE_OK",
	"MOVE_DENIED": "MOVE_DENIED",
	"INFO": "INFO",
	"WARN": "WARN",
	"ERROR": "ERROR",
}

const MESSAGE_COLORS := {
	GAME_MESSAGE.TURN_START: "#00FF00",
	GAME_MESSAGE.MOVE_OK: "#00FF00",
	GAME_MESSAGE.MOVE_DENIED: "#FF3B30",
	GAME_MESSAGE.INFO: "#FFFFFF",
	GAME_MESSAGE.WARN: "#FFCC00",
	GAME_MESSAGE.ERROR: "#FF3B30",
}

const POPUP_FLOW := {
	"INVITE_REQUEST": "invite_request",
}

const POPUP_ACTION := {
	"CONFIRM_YES": "confirm_yes",
	"CONFIRM_NO": "confirm_no",
}

static func color_for_message(code: String) -> Color:
	var hex := String(MESSAGE_COLORS.get(code, "#FFFFFF"))
	return Color.from_string(hex, Color.WHITE)

static func normalize_game_message(payload: Dictionary, default_code := GAME_MESSAGE.INFO) -> Dictionary:
	var normalized := InlineMessages.normalize_payload(payload, String(default_code))
	var ui_code := String(normalized.get("code", default_code)).strip_edges()
	if ui_code == "":
		ui_code = String(default_code)

	var params_val = payload.get("message_params", payload.get("params", payload.get("meta", {})))
	var params: Dictionary = params_val if params_val is Dictionary else {}
	var text := String(normalized.get("text", "")).strip_edges()
	var explicit_message_code := String(normalized.get("message_code", "")).strip_edges()
	if text.begins_with("MSG_INLINE_"):
		explicit_message_code = text
		text = InlineMessages.text_for_code(explicit_message_code, params)
	elif text.begins_with("MSG_POPUP_"):
		explicit_message_code = text
		text = PopupMessages.popup_text(explicit_message_code, params)
	if explicit_message_code != "":
		normalized["message_code"] = explicit_message_code
	normalized["text"] = text

	var color := color_for_message(ui_code)
	var color_val = payload.get("color", null)
	if color_val is Color:
		color = color_val
	elif color_val is String and String(color_val) != "":
		color = Color.from_string(String(color_val), color)
	normalized["color"] = color

	if String(normalized.get("text", "")).strip_edges() == "":
		var popup_code := String(normalized.get("message_code", "")).strip_edges()
		if popup_code != "":
			normalized["text"] = PopupMessages.popup_text(popup_code, params)

	return normalized

static func normalize_error_message(
	error: Dictionary,
	fallback_message := DEFAULT_ERROR_FALLBACK
) -> Dictionary:
	var popup_error := PopupMessages.resolve_error(error, fallback_message)
	return normalize_game_message(popup_error, String(popup_error.get("code", GAME_MESSAGE.ERROR)))

static func normalize_invite_response_ui(data: Dictionary) -> Dictionary:
	var ui_payload: Dictionary = data.get("ui", {}) as Dictionary
	return normalize_game_message(ui_payload, GAME_MESSAGE.INFO)

static func popup_code_from_error_code(error_code: String) -> String:
	return PopupMessages.popup_code_from_error_code(error_code)

static func invite_action_request(action_id: String, payload: Dictionary) -> Dictionary:
	var flow := String(payload.get("flow", ""))
	if flow != String(POPUP_FLOW["INVITE_REQUEST"]):
		return {}

	var from_user := String(payload.get("from", ""))
	if from_user == "":
		return {}

	if action_id == String(POPUP_ACTION["CONFIRM_YES"]):
		return { "to": from_user, "accepted": true }
	if action_id == String(POPUP_ACTION["CONFIRM_NO"]):
		return { "to": from_user, "accepted": false }
	return {}

static func is_inline_game_message(payload: Dictionary) -> bool:
	var normalized := normalize_game_message(payload)
	return InlineMessages.is_inline_message(normalized)

static func inline_message_color(payload: Dictionary) -> Color:
	var normalized := normalize_game_message(payload)
	return InlineMessages.color_for_payload(normalized)

static func game_end_popup_message(data: Dictionary, username: String, is_spectator: bool) -> Dictionary:
	return PopupMessages.game_end_popup_message(data, username, is_spectator)

static func game_end_popup_text(data: Dictionary, username: String, is_spectator: bool) -> String:
	var popup_msg := game_end_popup_message(data, username, is_spectator)
	return String(popup_msg.get("text", ""))
