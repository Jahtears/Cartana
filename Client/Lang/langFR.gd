extends RefCounted
class_name LangFR

const POPUP_TEXT_BY_CODE = {
	"POPUP_TECH_ERROR_GENERIC": "Erreur",
	"POPUP_TECH_BAD_REQUEST": "Requête invalide",
	"POPUP_TECH_NOT_FOUND": "Ressource introuvable",
	"POPUP_TECH_FORBIDDEN": "Action interdite",
	"POPUP_TECH_BAD_STATE": "Action impossible dans cet état",
	"POPUP_TECH_NOT_IMPLEMENTED": "Action non gérée",
	"POPUP_TECH_INTERNAL_ERROR": "Erreur serveur",

	"POPUP_AUTH_REQUIRED": "Authentification requise",
	"POPUP_AUTH_BAD_PIN": "PIN incorrect",
	"POPUP_AUTH_ALREADY_CONNECTED": "Utilisateur déjà connecté",
	"POPUP_AUTH_MISSING_CREDENTIALS": "Identifiant ou PIN manquant",
	"POPUP_AUTH_CONNECTION_ERROR": "Erreur de connexion",

	"POPUP_PLAYER_DISCONNECTED": "Connexion perdue",
	"POPUP_PLAYER_RECONNECTED": "Connexion rétablie",
	"POPUP_PLAYER_RECONNECT_FAIL": "Reconnexion échouée",

	"POPUP_INVITE_NOT_FOUND": "Invitation introuvable",
	"POPUP_INVITE_DECLINED": "{actor} a refusé ton invitation",
	"POPUP_INVITE_RECEIVED": "{from} t’invite à jouer",
	"POPUP_INVITE_SENT": "Invitation envoyée",
	"POPUP_INVITE_FAILED": "Invitation impossible",
	"POPUP_INVITE_CANCELLED": "Invitation annulée : {name} hors ligne",
	"POPUP_INVITE_TARGET_ALREADY_INVITED": "Le destinataire a déjà une invitation en attente",
	"POPUP_INVITE_TARGET_ALREADY_INVITING": "Le destinataire invite déjà quelqu’un",
	"POPUP_INVITE_ACTOR_ALREADY_INVITED": "Tu as déjà une invitation en attente",
	"POPUP_INVITE_ACTOR_ALREADY_INVITING": "Tu invites déjà quelqu’un",

	"POPUP_GAME_ENDED": "La partie est terminée",
	"POPUP_GAME_PAUSED": "La partie est en pause",
	"POPUP_GAME_END_VICTORY": "Victoire",
	"POPUP_GAME_END_DEFEAT": "Défaite",
	"POPUP_GAME_END_DRAW": "Match nul",
	"POPUP_GAME_END_ABANDON": "Fin de partie : abandon. Gagnant : {name}",
	"POPUP_GAME_END_DECK_EMPTY": "Fin de partie : deck vide. Gagnant : {name}",
	"POPUP_GAME_END_PILE_EMPTY": "Match nul : pioche vide",

	"POPUP_UI_ACTION_IMPOSSIBLE": "Action impossible",
	"POPUP_LOBBY_GET_PLAYERS_ERROR": "Erreur get_players",

	"POPUP_SPECTATE_CONFIRM": "Regarder cette partie en spectateur ?\nJoueurs : {players}",
	"POPUP_LOGOUT_CONFIRM": "Se déconnecter et revenir à l’écran de connexion ?",
	"POPUP_OPPONENT_DISCONNECTED": "{name} s’est déconnecté",
	"POPUP_OPPONENT_REJOINED": "{name} a rejoint la partie",
	"POPUP_QUIT_CONFIRM": "Quitter la partie et revenir au lobby ?",
	"POPUP_OPPONENT_DISCONNECTED_CHOICE": "{name} s’est déconnecté.\nAttendre ou revenir au lobby ?",
}

const INGAME_TEXT_BY_CODE = {
	"INGAME_MOVE_OK": "Valider",
	"INGAME_MOVE_DENIED": "Déplacement refusé",
	"INGAME_MOVE_INVALID_SLOT": "ID de slot invalide",
	"INGAME_MOVE_REJECTED": "ApplyMove rejeté",

	"INGAME_RULE_CARD_NOT_FOUND": "Carte introuvable",
	"INGAME_RULE_CARD_UNKNOWN": "Carte inconnue",
	"INGAME_RULE_SOURCE_SLOT_MISSING_CARD": "Carte absente du slot source",
	"INGAME_RULE_UNKNOWN_PLAYER": "Joueur inconnu pour cette partie",
	"INGAME_RULE_SLOT_VALIDATOR_MISSING": "Aucun validateur pour ce slot",
	"INGAME_RULE_TABLE_SLOT_NOT_FOUND": "Slot table introuvable",
	"INGAME_RULE_DECK_ONLY_TO_TABLE": "Carte du deck uniquement sur un slot table",
	"INGAME_RULE_NOT_YOUR_TURN": "Pas votre tour",
	"INGAME_RULE_BENCH_ONLY_TO_TABLE": "Carte du banc uniquement sur un slot table",
	"INGAME_RULE_ACE_BLOCKS_BENCH_DECK_TOP": "Banc interdit tant qu’un As est sur le dessus du deck",
	"INGAME_RULE_ACE_BLOCKS_BENCH_HAND": "Banc interdit tant qu’un As est en main",
	"INGAME_RULE_CARD_NOT_ALLOWED_ON_TABLE": "Carte interdite sur table attendu : {accepted}",
	"INGAME_RULE_CANNOT_PLAY_ON_DECK": "Interdit de jouer sur un deck",
	"INGAME_RULE_CANNOT_PLAY_ON_HAND": "Interdit de jouer sur la main",
	"INGAME_RULE_CANNOT_PLAY_ON_DRAWPILE": "Interdit de jouer sur la pioche",
	"INGAME_RULE_OPPONENT_SLOT_FORBIDDEN": "Slot adverse interdit",

	"INGAME_TURN_START_FIRST": "À vous de commencer",
	"INGAME_TURN_START": "À vous de jouer",
	"INGAME_TURN_TIMEOUT": "Temps écoulé",
}

const UI_LABELS = {
	"yes": "Oui",
	"no": "Non",
	"ok": "OK",
	"accept": "Accepter",
	"refuse": "Refuser",
	"cancel": "Annuler",
	"quit": "Quitter",
	"wait": "Attendre",
	"stay": "Rester",
	"revange": "Revanche",
	"back_lobby": "Retour lobby",
	"retry": "Se reconnecter",
}

static func popup_text(code: String, params: Dictionary = {}) -> String:
	var template := String(POPUP_TEXT_BY_CODE.get(String(code).strip_edges(), ""))
	if template == "":
		return ""
	return format_template(template, params)

static func ingame_text(code: String, params: Dictionary = {}) -> String:
	var template := String(INGAME_TEXT_BY_CODE.get(String(code).strip_edges(), ""))
	if template == "":
		return ""
	return format_template(template, params)

static func label(key: String, fallback := "") -> String:
	return String(UI_LABELS.get(String(key).strip_edges(), fallback))

static func format_template(template: String, params: Dictionary) -> String:
	var out := String(template)
	for key in params.keys():
		out = out.replace("{%s}" % String(key), String(params[key]))
	return out
