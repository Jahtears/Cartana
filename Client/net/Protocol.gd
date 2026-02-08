# Protocol.gd
extends Node

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

static func color_for_message(code: String) -> Color:
	var hex := String(MESSAGE_COLORS.get(code, "#FFFFFF"))
	return Color.from_string(hex, Color.WHITE)
