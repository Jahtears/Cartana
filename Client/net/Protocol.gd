# Protocol.gd
extends Node

const POPUP_PREFIX := "POPUP_"

const POPUP_TECH_ERROR_GENERIC := "POPUP_TECH_ERROR_GENERIC"
const POPUP_TECH_BAD_REQUEST := "POPUP_TECH_BAD_REQUEST"
const POPUP_TECH_NOT_FOUND := "POPUP_TECH_NOT_FOUND"
const POPUP_TECH_FORBIDDEN := "POPUP_TECH_FORBIDDEN"
const POPUP_TECH_BAD_STATE := "POPUP_TECH_BAD_STATE"
const POPUP_TECH_NOT_IMPLEMENTED := "POPUP_TECH_NOT_IMPLEMENTED"
const POPUP_TECH_INTERNAL_ERROR := "POPUP_TECH_INTERNAL_ERROR"

const POPUP_AUTH_REQUIRED := "POPUP_AUTH_REQUIRED"
const POPUP_AUTH_INVALID_USERNAME_MIN := "POPUP_AUTH_INVALID_USERNAME_MIN"
const POPUP_AUTH_INVALID_PIN_MIN := "POPUP_AUTH_INVALID_PIN_MIN"
const POPUP_AUTH_BAD_PIN := "POPUP_AUTH_BAD_PIN"
const POPUP_AUTH_MAX_TRY := "POPUP_AUTH_MAX_TRY"
const POPUP_AUTH_ALREADY_CONNECTED := "POPUP_AUTH_ALREADY_CONNECTED"
const POPUP_AUTH_MISSING_CREDENTIALS := "POPUP_AUTH_MISSING_CREDENTIALS"
const POPUP_AUTH_CONNECTION_ERROR := "POPUP_AUTH_CONNECTION_ERROR"
const POPUP_PLAYER_DISCONNECTED := "POPUP_PLAYER_DISCONNECTED"
const POPUP_PLAYER_RECONNECTED := "POPUP_PLAYER_RECONNECTED"
const POPUP_PLAYER_RECONNECT_FAIL := "POPUP_PLAYER_RECONNECT_FAIL"


const POPUP_INVITE_NOT_FOUND := "POPUP_INVITE_NOT_FOUND"
const POPUP_INVITE_DECLINED := "POPUP_INVITE_DECLINED"
const POPUP_INVITE_RECEIVED := "POPUP_INVITE_RECEIVED"
const POPUP_INVITE_SENT := "POPUP_INVITE_SENT"
const POPUP_INVITE_FAILED := "POPUP_INVITE_FAILED"
const POPUP_INVITE_CANCELLED := "POPUP_INVITE_CANCELLED"
const POPUP_INVITE_TARGET_ALREADY_INVITED := "POPUP_INVITE_TARGET_ALREADY_INVITED"
const POPUP_INVITE_TARGET_ALREADY_INVITING := "POPUP_INVITE_TARGET_ALREADY_INVITING"
const POPUP_INVITE_ACTOR_ALREADY_INVITED := "POPUP_INVITE_ACTOR_ALREADY_INVITED"
const POPUP_INVITE_ACTOR_ALREADY_INVITING := "POPUP_INVITE_ACTOR_ALREADY_INVITING"

const POPUP_GAME_PAUSED := "POPUP_GAME_PAUSED"
const POPUP_GAME_ENDED := "POPUP_GAME_ENDED"
const POPUP_GAME_END_VICTORY := "POPUP_GAME_END_VICTORY"
const POPUP_GAME_END_DEFEAT := "POPUP_GAME_END_DEFEAT"
const POPUP_GAME_END_DRAW := "POPUP_GAME_END_DRAW"
const POPUP_GAME_END_ABANDON := "POPUP_GAME_END_ABANDON"
const POPUP_GAME_END_DECK_EMPTY := "POPUP_GAME_END_DECK_EMPTY"
const POPUP_GAME_END_PILE_EMPTY := "POPUP_GAME_END_PILE_EMPTY"
const POPUP_GAME_END_TIMEOUT_STREAK := "POPUP_GAME_END_TIMEOUT_STREAK"
const GAME_END_REASON_ABANDON := "abandon"
const GAME_END_REASON_DECK_EMPTY := "deck_empty"
const GAME_END_REASON_PILE_EMPTY := "pile_empty"
const GAME_END_REASON_TIMEOUT_STREAK := "timeout_streak"

const POPUP_UI_ACTION_IMPOSSIBLE := "POPUP_UI_ACTION_IMPOSSIBLE"
const POPUP_LOBBY_GET_PLAYERS_ERROR := "POPUP_LOBBY_GET_PLAYERS_ERROR"
const POPUP_SPECTATE_CONFIRM := "POPUP_SPECTATE_CONFIRM"
const POPUP_LOGOUT_CONFIRM := "POPUP_LOGOUT_CONFIRM"
const POPUP_OPPONENT_DISCONNECTED := "POPUP_OPPONENT_DISCONNECTED"
const POPUP_OPPONENT_REJOINED := "POPUP_OPPONENT_REJOINED"
const POPUP_QUIT_CONFIRM := "POPUP_QUIT_CONFIRM"
const POPUP_OPPONENT_DISCONNECTED_CHOICE := "POPUP_OPPONENT_DISCONNECTED_CHOICE"

const DEFAULT_ERROR_FALLBACK := POPUP_UI_ACTION_IMPOSSIBLE

const POPUP_FLOW_INVITE_REQUEST := "invite_request"
const POPUP_ACTION_CONFIRM_YES := "confirm_yes"
const POPUP_ACTION_CONFIRM_NO := "confirm_no"
const POPUP_ACTION_INFO_OK := "info_ok"

const POPUP_FLOW := {
	"INVITE_REQUEST": POPUP_FLOW_INVITE_REQUEST,
}

const POPUP_ACTION := {
	"CONFIRM_YES": POPUP_ACTION_CONFIRM_YES,
	"CONFIRM_NO": POPUP_ACTION_CONFIRM_NO,
	"INFO_OK": POPUP_ACTION_INFO_OK,
}

static func normalize_popup_message(payload: Dictionary) -> Dictionary:
	var params := _extract_message_params(payload)
	var message_code := _extract_message_code(payload)
	var text_override := _extract_text(payload)

	if not message_code.begins_with(POPUP_PREFIX):
		if text_override != "":
			message_code = POPUP_TECH_ERROR_GENERIC
		else:
			message_code = DEFAULT_ERROR_FALLBACK

	var text := text_override
	if text == "" or text == message_code:
		text = popup_text(message_code, params)
	if text == "":
		text = popup_text(POPUP_TECH_ERROR_GENERIC)

	var normalized := {
		"text": text,
		"message_code": message_code,
		"message_params": params,
		"color": _extract_color(payload, Color.WHITE),
	}
	if text_override != "" and text_override != message_code:
		normalized["text_override"] = text_override
	return normalized

static func normalize_popup_error(error: Dictionary, fallback_message := DEFAULT_ERROR_FALLBACK) -> Dictionary:
	var top_params_val = error.get("message_params", {})
	var top_params: Dictionary = top_params_val if top_params_val is Dictionary else {}

	var message_code := String(error.get("message_code", "")).strip_edges()
	var text_override := String(error.get("text", "")).strip_edges()
	var fallback := String(fallback_message).strip_edges()

	if message_code == "":
		if fallback.begins_with(POPUP_PREFIX):
			message_code = fallback
		else:
			message_code = POPUP_TECH_ERROR_GENERIC
			if text_override == "":
				text_override = fallback

	if not message_code.begins_with(POPUP_PREFIX):
		if text_override == "":
			text_override = message_code
		message_code = POPUP_TECH_ERROR_GENERIC

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
	return String(POPUP_FLOW.get(key, fallback))

static func popup_action(key: String, fallback := "") -> String:
	return String(POPUP_ACTION.get(key, fallback))

static func normalize_invite_response_ui(data: Dictionary) -> Dictionary:
	var ui_payload_val = data.get("ui", {})
	var ui_payload: Dictionary = ui_payload_val if ui_payload_val is Dictionary else {}
	return normalize_popup_message(ui_payload)

static func invite_cancelled_ui(data: Dictionary) -> Dictionary:
	var user_name := String(data.get("name", "")).strip_edges()
	if user_name == "":
		user_name = LanguageManager.ui_text("UI_GENERIC_USER", "User")

	return normalize_popup_message({
		"message_code": POPUP_INVITE_CANCELLED,
		"message_params": {
			"name": user_name,
		},
	})

static func invite_action_request(action_id: String, payload: Dictionary) -> Dictionary:
	var flow := String(payload.get("flow", ""))
	if flow != POPUP_FLOW_INVITE_REQUEST:
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

	if action_id == POPUP_ACTION_CONFIRM_YES:
		req["accepted"] = true
		return req
	if action_id == POPUP_ACTION_CONFIRM_NO:
		req["accepted"] = false
		return req
	return {}

static func game_end_popup_message(data: Dictionary, username: String, is_spectator: bool) -> Dictionary:
	var winner := _safe_text(data.get("winner", ""))
	var reason := _safe_text(data.get("reason", "")).to_lower()
	if reason == "":
		reason = GAME_END_REASON_ABANDON

	if is_spectator:
		var spectator_code := _game_end_code_from_reason(reason)
		var spectator_params := {"name": winner if winner != "" else "-"}
		return {
			"message_code": spectator_code,
			"message_params": spectator_params,
		}

	if reason == GAME_END_REASON_PILE_EMPTY:
		return {
			"message_code": POPUP_GAME_END_DRAW,
			"message_params": {},
		}

	if winner == "":
		return {
			"message_code": POPUP_GAME_END_DRAW,
			"message_params": {},
		}

	if winner == _safe_text(username):
		return {
			"message_code": POPUP_GAME_END_VICTORY,
			"message_params": {},
		}

	return {
		"message_code": POPUP_GAME_END_DEFEAT,
		"message_params": {},
	}

static func _game_end_code_from_reason(reason: String) -> String:
	match reason:
		GAME_END_REASON_ABANDON:
			return POPUP_GAME_END_ABANDON
		GAME_END_REASON_DECK_EMPTY:
			return POPUP_GAME_END_DECK_EMPTY
		GAME_END_REASON_PILE_EMPTY:
			return POPUP_GAME_END_PILE_EMPTY
		GAME_END_REASON_TIMEOUT_STREAK:
			return POPUP_GAME_END_TIMEOUT_STREAK
		_:
			return POPUP_GAME_ENDED

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

static func _extract_color(payload: Dictionary, fallback: Color) -> Color:
	var color := fallback
	var color_val = payload.get("color", null)
	if color_val is Color:
		color = color_val
	elif color_val is String and String(color_val) != "":
		color = Color.from_string(String(color_val), color)
	return color
