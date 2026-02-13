extends RefCounted
class_name PopupMessages

const InlineMessages = preload("res://Client/game/messages/InlineMessages.gd")

const UI_CODE_INFO := "INFO"
const UI_CODE_WARN := "WARN"
const UI_CODE_ERROR := "ERROR"

const MSG_POPUP_TECH_ERROR_GENERIC := "MSG_POPUP_TECH_ERROR_GENERIC"
const MSG_POPUP_TECH_BAD_REQUEST := "MSG_POPUP_TECH_BAD_REQUEST"
const MSG_POPUP_TECH_NOT_FOUND := "MSG_POPUP_TECH_NOT_FOUND"
const MSG_POPUP_TECH_FORBIDDEN := "MSG_POPUP_TECH_FORBIDDEN"
const MSG_POPUP_TECH_BAD_STATE := "MSG_POPUP_TECH_BAD_STATE"
const MSG_POPUP_TECH_NOT_IMPLEMENTED := "MSG_POPUP_TECH_NOT_IMPLEMENTED"
const MSG_POPUP_TECH_INTERNAL_ERROR := "MSG_POPUP_TECH_INTERNAL_ERROR"

const MSG_POPUP_AUTH_REQUIRED := "MSG_POPUP_AUTH_REQUIRED"
const MSG_POPUP_AUTH_BAD_PIN := "MSG_POPUP_AUTH_BAD_PIN"
const MSG_POPUP_AUTH_ALREADY_CONNECTED := "MSG_POPUP_AUTH_ALREADY_CONNECTED"
const MSG_POPUP_AUTH_MISSING_CREDENTIALS := "MSG_POPUP_AUTH_MISSING_CREDENTIALS"
const MSG_POPUP_AUTH_CONNECTION_ERROR := "MSG_POPUP_AUTH_CONNECTION_ERROR"

const MSG_POPUP_INVITE_NOT_FOUND := "MSG_POPUP_INVITE_NOT_FOUND"
const MSG_POPUP_INVITE_BUSY := "MSG_POPUP_INVITE_BUSY"
const MSG_POPUP_INVITE_DECLINED := "MSG_POPUP_INVITE_DECLINED"
const MSG_POPUP_INVITE_RECEIVED := "MSG_POPUP_INVITE_RECEIVED"
const MSG_POPUP_INVITE_SENT := "MSG_POPUP_INVITE_SENT"
const MSG_POPUP_INVITE_FAILED := "MSG_POPUP_INVITE_FAILED"

const MSG_POPUP_GAME_ENDED := "MSG_POPUP_GAME_ENDED"
const MSG_POPUP_GAME_PAUSED := "MSG_POPUP_GAME_PAUSED"
const MSG_POPUP_GAME_END_WINNER := "MSG_POPUP_GAME_END_WINNER"
const MSG_POPUP_GAME_END_VICTORY := "MSG_POPUP_GAME_END_VICTORY"
const MSG_POPUP_GAME_END_DEFEAT := "MSG_POPUP_GAME_END_DEFEAT"

const MSG_POPUP_UI_ACTION_IMPOSSIBLE := "MSG_POPUP_UI_ACTION_IMPOSSIBLE"
const MSG_POPUP_LOBBY_GET_PLAYERS_ERROR := "MSG_POPUP_LOBBY_GET_PLAYERS_ERROR"
const MSG_POPUP_SPECTATE_CONFIRM := "MSG_POPUP_SPECTATE_CONFIRM"
const MSG_POPUP_LOGOUT_CONFIRM := "MSG_POPUP_LOGOUT_CONFIRM"
const MSG_POPUP_OPPONENT_DISCONNECTED := "MSG_POPUP_OPPONENT_DISCONNECTED"
const MSG_POPUP_OPPONENT_REJOINED := "MSG_POPUP_OPPONENT_REJOINED"
const MSG_POPUP_QUIT_CONFIRM := "MSG_POPUP_QUIT_CONFIRM"
const MSG_POPUP_OPPONENT_DISCONNECTED_CHOICE := "MSG_POPUP_OPPONENT_DISCONNECTED_CHOICE"

const TEXT_BY_CODE := {
	MSG_POPUP_TECH_ERROR_GENERIC: "Erreur",
	MSG_POPUP_TECH_BAD_REQUEST: "Requete invalide",
	MSG_POPUP_TECH_NOT_FOUND: "Ressource introuvable",
	MSG_POPUP_TECH_FORBIDDEN: "Action interdite",
	MSG_POPUP_TECH_BAD_STATE: "Action impossible dans cet etat",
	MSG_POPUP_TECH_NOT_IMPLEMENTED: "Action non geree",
	MSG_POPUP_TECH_INTERNAL_ERROR: "Erreur serveur",
	MSG_POPUP_AUTH_REQUIRED: "Authentification requise",
	MSG_POPUP_AUTH_BAD_PIN: "PIN incorrect",
	MSG_POPUP_AUTH_ALREADY_CONNECTED: "Utilisateur deja connecte",
	MSG_POPUP_AUTH_MISSING_CREDENTIALS: "Identifiant ou PIN manquant",
	MSG_POPUP_AUTH_CONNECTION_ERROR: "Erreur de connexion",
	MSG_POPUP_INVITE_NOT_FOUND: "Invitation introuvable",
	MSG_POPUP_INVITE_BUSY: "Action indisponible",
	MSG_POPUP_INVITE_DECLINED: "{actor} a refuse ton invitation",
	MSG_POPUP_INVITE_RECEIVED: "{from} t'invite a jouer",
	MSG_POPUP_INVITE_SENT: "Invitation envoyee",
	MSG_POPUP_INVITE_FAILED: "Invitation impossible",
	MSG_POPUP_GAME_ENDED: "La partie est terminee",
	MSG_POPUP_GAME_PAUSED: "La partie est en pause",
	MSG_POPUP_GAME_END_WINNER: "Gagnant: {name}",
	MSG_POPUP_GAME_END_VICTORY: "Victoire",
	MSG_POPUP_GAME_END_DEFEAT: "Défaite",
	MSG_POPUP_UI_ACTION_IMPOSSIBLE: "Action impossible",
	MSG_POPUP_LOBBY_GET_PLAYERS_ERROR: "Erreur get_players",
	MSG_POPUP_SPECTATE_CONFIRM: "Regarder cette partie en spectateur ?\n(game_id: {game_id})\nJoueurs: {players}",
	MSG_POPUP_LOGOUT_CONFIRM: "Se deconnecter et revenir a l'ecran de connexion ?",
	MSG_POPUP_OPPONENT_DISCONNECTED: "{name} s'est deconnecte",
	MSG_POPUP_OPPONENT_REJOINED: "{name} a rejoint la partie",
	MSG_POPUP_QUIT_CONFIRM: "Quitter la partie et revenir au lobby ?",
	MSG_POPUP_OPPONENT_DISCONNECTED_CHOICE: "{name} s'est deconnecte.\nAttendre ou revenir au lobby ?",
}

const ERROR_CODE_TO_POPUP_CODE := {
	"AUTH_REQUIRED": MSG_POPUP_AUTH_REQUIRED,
	"AUTH_BAD_PIN": MSG_POPUP_AUTH_BAD_PIN,
	"ALREADY_CONNECTED": MSG_POPUP_AUTH_ALREADY_CONNECTED,
	"BAD_REQUEST": MSG_POPUP_TECH_BAD_REQUEST,
	"NOT_FOUND": MSG_POPUP_TECH_NOT_FOUND,
	"FORBIDDEN": MSG_POPUP_TECH_FORBIDDEN,
	"BAD_STATE": MSG_POPUP_TECH_BAD_STATE,
	"GAME_END": MSG_POPUP_GAME_ENDED,
	"GAME_PAUSED": MSG_POPUP_GAME_PAUSED,
	"TURN_TIMEOUT": MSG_POPUP_TECH_BAD_STATE,
	"BUSY": MSG_POPUP_INVITE_BUSY,
	"NO_INVITE": MSG_POPUP_INVITE_NOT_FOUND,
	"NOT_IMPLEMENTED": MSG_POPUP_TECH_NOT_IMPLEMENTED,
	"SERVER_ERROR": MSG_POPUP_TECH_INTERNAL_ERROR,
}

const ERROR_CODE_TO_UI_CODE := {
	"BAD_STATE": UI_CODE_WARN,
	"GAME_END": UI_CODE_WARN,
	"GAME_PAUSED": UI_CODE_WARN,
	"TURN_TIMEOUT": UI_CODE_WARN,
	"BUSY": UI_CODE_WARN,
	"ALREADY_CONNECTED": UI_CODE_WARN,
	"NO_INVITE": UI_CODE_WARN,
}

static func popup_text(message_code: String, params: Dictionary = {}) -> String:
	var template := String(TEXT_BY_CODE.get(String(message_code).strip_edges(), ""))
	if template == "":
		return ""
	return _format_template(template, params)

static func popup_code_from_error_code(error_code: String) -> String:
	var clean := String(error_code).strip_edges()
	if clean == "":
		return MSG_POPUP_UI_ACTION_IMPOSSIBLE
	return String(ERROR_CODE_TO_POPUP_CODE.get(clean, MSG_POPUP_UI_ACTION_IMPOSSIBLE))

static func ui_code_from_error_code(error_code: String) -> String:
	var clean := String(error_code).strip_edges()
	if clean == "":
		return UI_CODE_ERROR
	return String(ERROR_CODE_TO_UI_CODE.get(clean, UI_CODE_ERROR))

static func resolve_error(error: Dictionary, fallback_message := MSG_POPUP_UI_ACTION_IMPOSSIBLE) -> Dictionary:
	var server_code := String(error.get("code", "")).strip_edges()
	var message_code := popup_code_from_error_code(server_code)
	var details_val = error.get("details", {})
	var details: Dictionary = details_val if details_val is Dictionary else {}
	var params_val = details.get("message_params", {})
	var message_params: Dictionary = params_val if params_val is Dictionary else {}

	var text := String(error.get("message", "")).strip_edges()
	if text == "":
		text = String(error.get("reason", "")).strip_edges()
	if text != "" and text.begins_with("MSG_INLINE_"):
		message_code = text
		text = InlineMessages.text_for_code(message_code, message_params)
	elif text != "" and text.begins_with("MSG_POPUP_"):
		message_code = text
		text = popup_text(message_code, message_params)
	if text == "":
		text = popup_text(message_code, message_params)
	if text == "":
		var fallback := String(fallback_message).strip_edges()
		if fallback.begins_with("MSG_INLINE_"):
			message_code = fallback
			text = InlineMessages.text_for_code(message_code, message_params)
		elif fallback.begins_with("MSG_POPUP_"):
			message_code = fallback
			text = popup_text(message_code, message_params)
		else:
			text = fallback
			if message_code == "":
				message_code = MSG_POPUP_UI_ACTION_IMPOSSIBLE
	if text == "":
		message_code = MSG_POPUP_UI_ACTION_IMPOSSIBLE
		text = popup_text(message_code)

	return {
		"text": text,
		"code": ui_code_from_error_code(server_code),
		"message_code": message_code,
		"message_params": message_params,
	}

static func game_end_popup_message(data: Dictionary, username: String, is_spectator: bool) -> Dictionary:
	var winner := String(data.get("winner", "")).strip_edges()
	var winner_name := winner if winner != "" else "-"

	if is_spectator:
		return {
			"message_code": MSG_POPUP_GAME_END_WINNER,
			"code": UI_CODE_INFO,
			"text": popup_text(MSG_POPUP_GAME_END_WINNER, { "name": winner_name }),
		}

	if winner != "" and winner == username:
		return {
			"message_code": MSG_POPUP_GAME_END_VICTORY,
			"code": UI_CODE_INFO,
			"text": popup_text(MSG_POPUP_GAME_END_VICTORY),
		}

	if winner != "":
		return {
			"message_code": MSG_POPUP_GAME_END_DEFEAT,
			"code": UI_CODE_INFO,
			"text": popup_text(MSG_POPUP_GAME_END_DEFEAT),
		}

	return {
		"message_code": MSG_POPUP_GAME_END_WINNER,
		"code": UI_CODE_INFO,
		"text": popup_text(MSG_POPUP_GAME_END_WINNER, { "name": winner_name }),
	}

static func _format_template(template: String, params: Dictionary) -> String:
	var out := String(template)
	for key in params.keys():
		out = out.replace("{%s}" % String(key), String(params[key]))
	return out
