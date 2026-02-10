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

const ERROR_UI_BY_CODE := {
	"BAD_STATE": GAME_MESSAGE.WARN,
	"GAME_END": GAME_MESSAGE.WARN,
	"GAME_PAUSED": GAME_MESSAGE.WARN,
	"TURN_TIMEOUT": GAME_MESSAGE.WARN,
	"BUSY": GAME_MESSAGE.WARN,
	"ALREADY_CONNECTED": GAME_MESSAGE.WARN,
	"NO_INVITE": GAME_MESSAGE.WARN,
}

const ERROR_TEXT_BY_CODE := {
	"AUTH_REQUIRED": "Authentification requise.",
	"AUTH_BAD_PIN": "PIN incorrect.",
	"ALREADY_CONNECTED": "Utilisateur deja connecte.",
	"BAD_REQUEST": "Requete invalide.",
	"NOT_FOUND": "Ressource introuvable.",
	"FORBIDDEN": "Action interdite.",
	"BAD_STATE": "Action impossible dans cet etat.",
	"GAME_END": "La partie est terminee.",
	"GAME_PAUSED": "La partie est en pause.",
	"TURN_TIMEOUT": "Temps ecoule.",
	"NO_INVITE": "Invitation introuvable.",
	"BUSY": "Action indisponible.",
	"NOT_IMPLEMENTED": "Action non geree.",
	"SERVER_ERROR": "Erreur serveur.",
}

static func color_for_message(code: String) -> Color:
	var hex := String(MESSAGE_COLORS.get(code, "#FFFFFF"))
	return Color.from_string(hex, Color.WHITE)

static func message_text(payload: Dictionary, fallback := "") -> String:
	var text := String(payload.get("text", "")).strip_edges()
	if text == "":
		text = String(payload.get("message", "")).strip_edges()
	if text == "":
		text = String(payload.get("reason", "")).strip_edges()
	if text == "":
		text = String(fallback)
	return text

static func normalize_game_message(payload: Dictionary, default_code := GAME_MESSAGE.INFO) -> Dictionary:
	var text := message_text(payload, "")
	var code := String(payload.get("code", default_code))
	var color := color_for_message(code)
	var color_val = payload.get("color", null)

	if color_val is Color:
		color = color_val
	elif color_val is String and String(color_val) != "":
		color = Color.from_string(String(color_val), color)

	return {
		"text": text,
		"code": code,
		"color": color,
	}

static func normalize_error_message(error: Dictionary, fallback_text := "Action impossible") -> Dictionary:
	var code := String(error.get("code", "")).strip_edges()
	var text := message_text(error, "")
	if text == "" and code != "":
		text = String(ERROR_TEXT_BY_CODE.get(code, ""))
	if text == "":
		text = String(fallback_text)

	var ui_code := String(ERROR_UI_BY_CODE.get(code, GAME_MESSAGE.ERROR))
	return normalize_game_message({"text": text, "code": ui_code}, GAME_MESSAGE.ERROR)
