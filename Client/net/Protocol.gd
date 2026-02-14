# Protocol.gd
extends Node

const GameMessage = preload("res://Client/game/messages/GameMessage.gd")

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
const MSG_POPUP_INVITE_DECLINED := "MSG_POPUP_INVITE_DECLINED"
const MSG_POPUP_INVITE_RECEIVED := "MSG_POPUP_INVITE_RECEIVED"
const MSG_POPUP_INVITE_SENT := "MSG_POPUP_INVITE_SENT"
const MSG_POPUP_INVITE_FAILED := "MSG_POPUP_INVITE_FAILED"
const MSG_POPUP_INVITE_CANCELLED := "MSG_POPUP_INVITE_CANCELLED"
const MSG_POPUP_INVITE_TARGET_ALREADY_INVITED := "MSG_POPUP_INVITE_TARGET_ALREADY_INVITED"
const MSG_POPUP_INVITE_TARGET_ALREADY_INVITING := "MSG_POPUP_INVITE_TARGET_ALREADY_INVITING"
const MSG_POPUP_INVITE_ACTOR_ALREADY_INVITED := "MSG_POPUP_INVITE_ACTOR_ALREADY_INVITED"
const MSG_POPUP_INVITE_ACTOR_ALREADY_INVITING := "MSG_POPUP_INVITE_ACTOR_ALREADY_INVITING"

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

const DEFAULT_ERROR_FALLBACK := MSG_POPUP_UI_ACTION_IMPOSSIBLE

const POPUP_FLOW := {
	"INVITE_REQUEST": "invite_request",
}

const POPUP_ACTION := {
	"CONFIRM_YES": "confirm_yes",
	"CONFIRM_NO": "confirm_no",
}

const POPUP_TEXT_BY_CODE := {
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
	MSG_POPUP_INVITE_DECLINED: "{actor} a refuse ton invitation",
	MSG_POPUP_INVITE_RECEIVED: "{from} t'invite a jouer",
	MSG_POPUP_INVITE_SENT: "Invitation envoyé",
	MSG_POPUP_INVITE_FAILED: "Invitation impossible",
	MSG_POPUP_INVITE_CANCELLED: "Invitation annulee: {name} hors ligne",
	MSG_POPUP_INVITE_TARGET_ALREADY_INVITED: "Le destinataire a deja une invitation en attente",
	MSG_POPUP_INVITE_TARGET_ALREADY_INVITING: "Le destinataire invite deja quelqu'un",
	MSG_POPUP_INVITE_ACTOR_ALREADY_INVITED: "Tu as deja une invitation en attente",
	MSG_POPUP_INVITE_ACTOR_ALREADY_INVITING: "Tu invites deja quelqu'un",
	MSG_POPUP_GAME_ENDED: "La partie est terminee",
	MSG_POPUP_GAME_PAUSED: "La partie est en pause",
	MSG_POPUP_GAME_END_WINNER: "Gagnant: {name}",
	MSG_POPUP_GAME_END_VICTORY: "Victoire",
	MSG_POPUP_GAME_END_DEFEAT: "Defaite",
	MSG_POPUP_UI_ACTION_IMPOSSIBLE: "Action impossible",
	MSG_POPUP_LOBBY_GET_PLAYERS_ERROR: "Erreur get_players",
	MSG_POPUP_SPECTATE_CONFIRM: "Regarder cette partie en spectateur ?\n(game_id: {game_id})\nJoueurs: {players}",
	MSG_POPUP_LOGOUT_CONFIRM: "Se deconnecter et revenir a l'ecran de connexion ?",
	MSG_POPUP_OPPONENT_DISCONNECTED: "{name} s'est deconnecte",
	MSG_POPUP_OPPONENT_REJOINED: "{name} a rejoint la partie",
	MSG_POPUP_QUIT_CONFIRM: "Quitter la partie et revenir au lobby ?",
	MSG_POPUP_OPPONENT_DISCONNECTED_CHOICE: "{name} s'est deconnecte.\nAttendre ou revenir au lobby ?",
}

static func normalize_game_message(payload: Dictionary) -> Dictionary:
	var inline := GameMessage.normalize_inline_message(payload)
	if not inline.is_empty():
		return inline

	var params_val = payload.get(
		"message_params",
		payload.get("params", payload.get("meta", {}))
	)
	var params: Dictionary = params_val if params_val is Dictionary else {}
	var text := String(payload.get("text", "")).strip_edges()
	if text == "":
		text = String(payload.get("message", "")).strip_edges()
	var message_code := String(payload.get("message_code", "")).strip_edges()

	if text.begins_with("MSG_POPUP_"):
		message_code = text

	if message_code.begins_with("MSG_POPUP_") and (text == "" or text == message_code):
		text = popup_text(message_code, params)

	var color := Color.WHITE
	var color_val = payload.get("color", null)
	if color_val is Color:
		color = color_val
	elif color_val is String and String(color_val) != "":
		color = Color.from_string(String(color_val), color)

	return {
		"text": text,
		"message_code": message_code,
		"message_params": params,
		"color": color,
	}

static func normalize_error_message(
	error: Dictionary,
	fallback_message := DEFAULT_ERROR_FALLBACK
) -> Dictionary:
	var details_val = error.get("details", {})
	var details: Dictionary = details_val if details_val is Dictionary else {}
	var top_params_val = error.get("message_params", {})
	var top_params: Dictionary = top_params_val if top_params_val is Dictionary else {}
	var details_params_val = details.get("message_params", {})
	var details_params: Dictionary = details_params_val if details_params_val is Dictionary else {}
	var message_params: Dictionary = {}
	for key in details_params.keys():
		message_params[key] = details_params[key]
	for key in top_params.keys():
		message_params[key] = top_params[key]

	var message_code := String(error.get("message_code", "")).strip_edges()
	var text := String(error.get("text", "")).strip_edges()

	var fallback := String(fallback_message).strip_edges()
	if message_code == "":
		if fallback.begins_with("MSG_INLINE_") or fallback.begins_with("MSG_POPUP_"):
			message_code = fallback
		else:
			message_code = MSG_POPUP_UI_ACTION_IMPOSSIBLE
			if text == "":
				text = fallback

	if message_code == "":
		message_code = MSG_POPUP_UI_ACTION_IMPOSSIBLE

	if text == "":
		if message_code.begins_with("MSG_INLINE_"):
			text = GameMessage.text_for_code(message_code, message_params)
		elif message_code.begins_with("MSG_POPUP_"):
			text = popup_text(message_code, message_params)

	if text == "":
		text = popup_text(MSG_POPUP_UI_ACTION_IMPOSSIBLE)
	if text == "":
		text = "Erreur"

	return normalize_game_message({
		"text": text,
		"message_code": message_code,
		"message_params": message_params,
	})

static func popup_text(message_code: String, params: Dictionary = {}) -> String:
	var template := String(POPUP_TEXT_BY_CODE.get(String(message_code).strip_edges(), ""))
	if template == "":
		return ""
	return _format_template(template, params)

static func popup_flow(key: String, fallback := "") -> String:
	return String(POPUP_FLOW.get(key, fallback))

static func popup_action(key: String, fallback := "") -> String:
	return String(POPUP_ACTION.get(key, fallback))

static func normalize_invite_response_ui(data: Dictionary) -> Dictionary:
	var ui_payload: Dictionary = data.get("ui", {}) as Dictionary
	return normalize_game_message(ui_payload)

static func invite_cancelled_ui(data: Dictionary) -> Dictionary:
	var name := String(data.get("from", "")).strip_edges()
	if name == "":
		name = String(data.get("to", "")).strip_edges()
	if name == "":
		name = "Utilisateur"

	return normalize_game_message({
		"message_code": MSG_POPUP_INVITE_CANCELLED,
		"message_params": {
			"name": name,
		},
	})

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
	return not GameMessage.normalize_inline_message(payload).is_empty()

static func inline_message_color(payload: Dictionary) -> Color:
	var normalized := GameMessage.normalize_inline_message(payload)
	if normalized.is_empty():
		return Color.WHITE
	var color_val = normalized.get("color", null)
	if color_val is Color:
		return color_val
	return Color.WHITE

static func game_end_popup_message(data: Dictionary, username: String, is_spectator: bool) -> Dictionary:
	var winner := String(data.get("winner", "")).strip_edges()
	var winner_name := winner if winner != "" else "-"

	if is_spectator:
		return {
			"message_code": MSG_POPUP_GAME_END_WINNER,
			"text": popup_text(MSG_POPUP_GAME_END_WINNER, { "name": winner_name }),
		}

	if winner != "" and winner == username:
		return {
			"message_code": MSG_POPUP_GAME_END_VICTORY,
			"text": popup_text(MSG_POPUP_GAME_END_VICTORY),
		}

	if winner != "":
		return {
			"message_code": MSG_POPUP_GAME_END_DEFEAT,
			"text": popup_text(MSG_POPUP_GAME_END_DEFEAT),
		}

	return {
		"message_code": MSG_POPUP_GAME_END_WINNER,
		"text": popup_text(MSG_POPUP_GAME_END_WINNER, { "name": winner_name }),
	}

static func _format_template(template: String, params: Dictionary) -> String:
	var out := String(template)
	for key in params.keys():
		out = out.replace("{%s}" % String(key), String(params[key]))
	return out
