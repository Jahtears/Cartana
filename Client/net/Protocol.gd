# Protocol.gd
extends Node

const MessageResolver = preload("res://Client/game/messages/MessageResolver.gd")
const PopupMessages = preload("res://Client/game/messages/PopupMessages.gd")
const DEFAULT_ERROR_FALLBACK := "MSG_POPUP_UI_ACTION_IMPOSSIBLE"

const GAME_MESSAGE := MessageResolver.GAME_MESSAGE

const MESSAGE_COLORS := MessageResolver.MESSAGE_COLORS
const POPUP_FLOW := MessageResolver.POPUP_FLOW
const POPUP_ACTION := MessageResolver.POPUP_ACTION

static func color_for_message(code: String) -> Color:
	return MessageResolver.color_for_message(code)

static func normalize_game_message(payload: Dictionary, default_code := GAME_MESSAGE.INFO) -> Dictionary:
	return MessageResolver.normalize_game_message(payload, default_code)

static func normalize_error_message(
	error: Dictionary,
	fallback_message := DEFAULT_ERROR_FALLBACK
) -> Dictionary:
	return MessageResolver.normalize_error_message(error, fallback_message)

static func popup_text(message_code: String, params: Dictionary = {}) -> String:
	return PopupMessages.popup_text(message_code, params)

static func normalize_invite_response_ui(data: Dictionary) -> Dictionary:
	return MessageResolver.normalize_invite_response_ui(data)

static func invite_action_request(action_id: String, payload: Dictionary) -> Dictionary:
	return MessageResolver.invite_action_request(action_id, payload)

static func is_inline_game_message(payload: Dictionary) -> bool:
	return MessageResolver.is_inline_game_message(payload)

static func inline_message_color(payload: Dictionary) -> Color:
	return MessageResolver.inline_message_color(payload)

static func game_end_popup_text(data: Dictionary, username: String, is_spectator: bool) -> String:
	return MessageResolver.game_end_popup_text(data, username, is_spectator)
