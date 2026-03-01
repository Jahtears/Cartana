extends RefCounted
class_name LangENGLISH

const POPUP_TEXT_BY_CODE = {
	"POPUP_TECH_ERROR_GENERIC": "Error",
	"POPUP_TECH_BAD_REQUEST": "Invalid request",
	"POPUP_TECH_NOT_FOUND": "Resource not found",
	"POPUP_TECH_FORBIDDEN": "Action forbidden",
	"POPUP_TECH_BAD_STATE": "Action impossible in this state",
	"POPUP_TECH_NOT_IMPLEMENTED": "Action not implemented",
	"POPUP_TECH_INTERNAL_ERROR": "Server error",

	"POPUP_AUTH_REQUIRED": "Authentication required",
	"POPUP_AUTH_BAD_PIN": "Incorrect PIN",
	"POPUP_AUTH_MAX_TRY": "Too many attempts. Try again in {retry_after_s}s",
	"POPUP_AUTH_ALREADY_CONNECTED": "User already connected",
	"POPUP_AUTH_MISSING_CREDENTIALS": "Missing username or PIN",
	"POPUP_AUTH_CONNECTION_ERROR": "Connection error",

	"POPUP_PLAYER_DISCONNECTED": "Connection lost",
	"POPUP_PLAYER_RECONNECTED": "Connection restored",
	"POPUP_PLAYER_RECONNECT_FAIL": "Reconnection failed",

	"POPUP_INVITE_NOT_FOUND": "Invitation not found",
	"POPUP_INVITE_DECLINED": "{actor} declined your invitation",
	"POPUP_INVITE_RECEIVED": "{from} invites you to play",
	"POPUP_INVITE_SENT": "Invitation sent",
	"POPUP_INVITE_FAILED": "Invitation failed",
	"POPUP_INVITE_CANCELLED": "Invitation cancelled: {name} offline",
	"POPUP_INVITE_TARGET_ALREADY_INVITED": "The recipient already has a pending invitation",
	"POPUP_INVITE_TARGET_ALREADY_INVITING": "The recipient is already inviting someone",
	"POPUP_INVITE_ACTOR_ALREADY_INVITED": "You already have a pending invitation",
	"POPUP_INVITE_ACTOR_ALREADY_INVITING": "You are already inviting someone",

	"POPUP_GAME_ENDED": "The game has ended",
	"POPUP_GAME_PAUSED": "The game is paused",
	"POPUP_GAME_END_VICTORY": "Victory",
	"POPUP_GAME_END_DEFEAT": "Defeat",
	"POPUP_GAME_END_DRAW": "Draw",
	"POPUP_GAME_END_ABANDON": "Game over: abandon. Winner: {name}",
	"POPUP_GAME_END_DECK_EMPTY": "Game over: empty deck. Winner: {name}",
	"POPUP_GAME_END_PILE_EMPTY": "Draw: empty draw pile",
	"POPUP_GAME_END_TIMEOUT_STREAK": "Game over: 3 consecutive timeouts. Winner: {name}",

	"POPUP_UI_ACTION_IMPOSSIBLE": "Action impossible",
	"POPUP_LOBBY_GET_PLAYERS_ERROR": "get_players error",

	"POPUP_SPECTATE_CONFIRM": "Watch this game as a spectator?\n(game_id: {game_id})\nPlayers: {players}",
	"POPUP_LOGOUT_CONFIRM": "Log out and return to the login screen?",
	"POPUP_OPPONENT_DISCONNECTED": "{name} disconnected",
	"POPUP_OPPONENT_REJOINED": "{name} rejoined the game",
	"POPUP_QUIT_CONFIRM": "Quit the game and return to the lobby?",
	"POPUP_OPPONENT_DISCONNECTED_CHOICE": "{name} disconnected.\nWait or return to the lobby?",
}

const RULE_TEXT_BY_CODE = {
	"RULE_OK": "Confirm",
	"RULE_MOVE_DENIED": "Move denied",
	"RULE_DECK_TO_TABLE": "Deck cards can only be played on a Table slot",
	"RULE_NOT_YOUR_TURN": "Not your turn",
	"RULE_BENCH_TO_TABLE": "Bench cards can only be played on a Table slot",
	"RULE_ACE_ON_DECK": "Bench forbidden while an Ace is on top of the deck",
	"RULE_ACE_IN_HAND": "Bench forbidden while holding an Ace",
	"RULE_ALLOWED_ON_TABLE": "Card not allowed on Table (expected: {accepted})",
	"RULE_OPPONENT_SLOT_FORBIDDEN": "Opponent slot forbidden",

	"RULE_TURN_START_FIRST": "You start",
	"RULE_TURN_START": "Your turn",
	"RULE_TURN_TIMEOUT": "Time’s up",
}

const UI_LABELS = {
	"yes": "Yes",
	"no": "No",
	"ok": "OK",
	"accept": "Accept",
	"refuse": "Refuse",
	"cancel": "Cancel",
	"quit": "Quit",
	"wait": "Wait",
	"stay": "Stay",
	"rematch": "Rematch",
	"back_lobby": "Back to lobby",
	"retry": "Reconnect",
}

static func popup_text(code: String, params: Dictionary = {}) -> String:
	var template := String(POPUP_TEXT_BY_CODE.get(String(code).strip_edges(), ""))
	if template == "":
		return ""
	return format_template(template, params)

static func rule_text(code: String, params: Dictionary = {}) -> String:
	var template := String(RULE_TEXT_BY_CODE.get(String(code).strip_edges(), ""))
	if template == "":
		return ""
	return format_template(template, params)

static func label(key: String, fallback := "") -> String:
	return String(UI_LABELS.get(String(key).strip_edges(), fallback))

static func format_template(template: String, params: Dictionary) -> String:
	var out := String(template)
	for key in params.keys():
		out = out.replace("{%s}" % str(key), str(params[key]))
	return out
