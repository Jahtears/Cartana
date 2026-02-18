# Protocol.gd
extends Node

const GameMessage = preload("res://Client/game/helpers/GameMessage.gd")

const POPUP_TECH_ERROR_GENERIC := "POPUP_TECH_ERROR_GENERIC"
const POPUP_TECH_BAD_REQUEST := "POPUP_TECH_BAD_REQUEST"
const POPUP_TECH_NOT_FOUND := "POPUP_TECH_NOT_FOUND"
const POPUP_TECH_FORBIDDEN := "POPUP_TECH_FORBIDDEN"
const POPUP_TECH_BAD_STATE := "POPUP_TECH_BAD_STATE"
const POPUP_TECH_NOT_IMPLEMENTED := "POPUP_TECH_NOT_IMPLEMENTED"
const POPUP_TECH_INTERNAL_ERROR := "POPUP_TECH_INTERNAL_ERROR"

const POPUP_AUTH_REQUIRED := "POPUP_AUTH_REQUIRED"
const POPUP_AUTH_BAD_PIN := "POPUP_AUTH_BAD_PIN"
const POPUP_AUTH_ALREADY_CONNECTED := "POPUP_AUTH_ALREADY_CONNECTED"
const POPUP_AUTH_MISSING_CREDENTIALS := "POPUP_AUTH_MISSING_CREDENTIALS"
const POPUP_AUTH_CONNECTION_ERROR := "POPUP_AUTH_CONNECTION_ERROR"

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

const POPUP_GAME_ENDED := "POPUP_GAME_ENDED"
const POPUP_GAME_PAUSED := "POPUP_GAME_PAUSED"
const POPUP_GAME_END_WINNER := "POPUP_GAME_END_WINNER"
const POPUP_GAME_END_VICTORY := "POPUP_GAME_END_VICTORY"
const POPUP_GAME_END_DEFEAT := "POPUP_GAME_END_DEFEAT"

const POPUP_UI_ACTION_IMPOSSIBLE := "POPUP_UI_ACTION_IMPOSSIBLE"
const POPUP_LOBBY_GET_PLAYERS_ERROR := "POPUP_LOBBY_GET_PLAYERS_ERROR"
const POPUP_SPECTATE_CONFIRM := "POPUP_SPECTATE_CONFIRM"
const POPUP_LOGOUT_CONFIRM := "POPUP_LOGOUT_CONFIRM"
const POPUP_OPPONENT_DISCONNECTED := "POPUP_OPPONENT_DISCONNECTED"
const POPUP_OPPONENT_REJOINED := "POPUP_OPPONENT_REJOINED"
const POPUP_QUIT_CONFIRM := "POPUP_QUIT_CONFIRM"
const POPUP_OPPONENT_DISCONNECTED_CHOICE := "POPUP_OPPONENT_DISCONNECTED_CHOICE"

const DEFAULT_ERROR_FALLBACK := POPUP_UI_ACTION_IMPOSSIBLE

const POPUP_FLOW := {
	"INVITE_REQUEST": "invite_request",
}

const POPUP_ACTION := {
	"CONFIRM_YES": "confirm_yes",
	"CONFIRM_NO": "confirm_no",
}

const POPUP_TEXT_BY_CODE := {
	POPUP_TECH_ERROR_GENERIC: "Erreur",
	POPUP_TECH_BAD_REQUEST: "Requete invalide",
	POPUP_TECH_NOT_FOUND: "Ressource introuvable",
	POPUP_TECH_FORBIDDEN: "Action interdite",
	POPUP_TECH_BAD_STATE: "Action impossible dans cet etat",
	POPUP_TECH_NOT_IMPLEMENTED: "Action non geree",
	POPUP_TECH_INTERNAL_ERROR: "Erreur serveur",
	POPUP_AUTH_REQUIRED: "Authentification requise",
	POPUP_AUTH_BAD_PIN: "PIN incorrect",
	POPUP_AUTH_ALREADY_CONNECTED: "Utilisateur deja connecte",
	POPUP_AUTH_MISSING_CREDENTIALS: "Identifiant ou PIN manquant",
	POPUP_AUTH_CONNECTION_ERROR: "Erreur de connexion",
	POPUP_INVITE_NOT_FOUND: "Invitation introuvable",
	POPUP_INVITE_DECLINED: "{actor} a refuse ton invitation",
	POPUP_INVITE_RECEIVED: "{from} t'invite a jouer",
	POPUP_INVITE_SENT: "Invitation envoyé",
	POPUP_INVITE_FAILED: "Invitation impossible",
	POPUP_INVITE_CANCELLED: "Invitation annulee: {name} hors ligne",
	POPUP_INVITE_TARGET_ALREADY_INVITED: "Le destinataire a deja une invitation en attente",
	POPUP_INVITE_TARGET_ALREADY_INVITING: "Le destinataire invite deja quelqu'un",
	POPUP_INVITE_ACTOR_ALREADY_INVITED: "Tu as deja une invitation en attente",
	POPUP_INVITE_ACTOR_ALREADY_INVITING: "Tu invites deja quelqu'un",
	POPUP_GAME_ENDED: "La partie est terminee",
	POPUP_GAME_PAUSED: "La partie est en pause",
	POPUP_GAME_END_WINNER: "Gagnant: {name}",
	POPUP_GAME_END_VICTORY: "Victoire",
	POPUP_GAME_END_DEFEAT: "Defaite",
	POPUP_UI_ACTION_IMPOSSIBLE: "Action impossible",
	POPUP_LOBBY_GET_PLAYERS_ERROR: "Erreur get_players",
	POPUP_SPECTATE_CONFIRM: "Regarder cette partie en spectateur ?\n(game_id: {game_id})\nJoueurs: {players}",
	POPUP_LOGOUT_CONFIRM: "Se deconnecter et revenir a l'ecran de connexion ?",
	POPUP_OPPONENT_DISCONNECTED: "{name} s'est deconnecte",
	POPUP_OPPONENT_REJOINED: "{name} a rejoint la partie",
	POPUP_QUIT_CONFIRM: "Quitter la partie et revenir au lobby ?",
	POPUP_OPPONENT_DISCONNECTED_CHOICE: "{name} s'est deconnecte.\nAttendre ou revenir au lobby ?",
}

static func normalize_game_message(payload: Dictionary) -> Dictionary:
	var ingame := GameMessage.normalize_ingame_message(payload)
	if not ingame.is_empty():
		return ingame

	var params_val = payload.get(
		"message_params",
		payload.get("params", payload.get("meta", {}))
	)
	var params: Dictionary = params_val if params_val is Dictionary else {}
	var text := String(payload.get("text", "")).strip_edges()
	if text == "":
		text = String(payload.get("message", "")).strip_edges()
	var message_code := String(payload.get("message_code", "")).strip_edges()

	if text.begins_with("POPUP_"):
		message_code = text

	if message_code.begins_with("POPUP_") and (text == "" or text == message_code):
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
		if fallback.begins_with("INGAME_") or fallback.begins_with("POPUP_"):
			message_code = fallback
		else:
			message_code = POPUP_UI_ACTION_IMPOSSIBLE
			if text == "":
				text = fallback

	if message_code == "":
		message_code = POPUP_UI_ACTION_IMPOSSIBLE

	if text == "":
		if message_code.begins_with("INGAME_"):
			text = GameMessage.text_for_code(message_code, message_params)
		elif message_code.begins_with("POPUP_"):
			text = popup_text(message_code, message_params)

	if text == "":
		text = popup_text(POPUP_UI_ACTION_IMPOSSIBLE)
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
		"message_code": POPUP_INVITE_CANCELLED,
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

static func is_ingame_game_message(payload: Dictionary) -> bool:
	return not GameMessage.normalize_ingame_message(payload).is_empty()

static func ingame_message_color(payload: Dictionary) -> Color:
	var normalized := GameMessage.normalize_ingame_message(payload)
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
			"message_code": POPUP_GAME_END_WINNER,
			"text": popup_text(POPUP_GAME_END_WINNER, { "name": winner_name }),
		}

	if winner != "" and winner == username:
		return {
			"message_code": POPUP_GAME_END_VICTORY,
			"text": popup_text(POPUP_GAME_END_VICTORY),
		}

	if winner != "":
		return {
			"message_code": POPUP_GAME_END_DEFEAT,
			"text": popup_text(POPUP_GAME_END_DEFEAT),
		}

	return {
		"message_code": POPUP_GAME_END_WINNER,
		"text": popup_text(POPUP_GAME_END_WINNER, { "name": winner_name }),
	}

static func _format_template(template: String, params: Dictionary) -> String:
	var out := String(template)
	for key in params.keys():
		out = out.replace("{%s}" % String(key), String(params[key]))
	return out
