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

	"POPUP_UI_ACTION_IMPOSSIBLE": "Action impossible",
	"POPUP_LOBBY_GET_PLAYERS_ERROR": "get_players error",

	"POPUP_SPECTATE_CONFIRM": "Watch this game as a spectator?\n(game_id: {game_id})\nPlayers: {players}",
	"POPUP_LOGOUT_CONFIRM": "Log out and return to the login screen?",
	"POPUP_OPPONENT_DISCONNECTED": "{name} disconnected",
	"POPUP_OPPONENT_REJOINED": "{name} rejoined the game",
	"POPUP_QUIT_CONFIRM": "Quit the game and return to the lobby?",
	"POPUP_OPPONENT_DISCONNECTED_CHOICE": "{name} disconnected.\nWait or return to the lobby?",
}

const INGAME_TEXT_BY_CODE = {
	"INGAME_RULE_OK": "Confirm",
	"INGAME_MOVE_DENIED": "Move denied",
	"INGAME_RULE_DECK_ONLY_TO_TABLE": "Deck cards can only be played on a Table slot",
	"INGAME_RULE_NOT_YOUR_TURN": "Not your turn",
	"INGAME_RULE_BENCH_ONLY_TO_TABLE": "Bench cards can only be played on a Table slot",
	"INGAME_RULE_ACE_BLOCKS_BENCH_DECK_TOP": "Bench forbidden while an Ace is on top of the deck",
	"INGAME_RULE_ACE_BLOCKS_BENCH_HAND": "Bench forbidden while holding an Ace",
	"INGAME_RULE_CARD_NOT_ALLOWED_ON_TABLE": "Card not allowed on Table (expected: {accepted})",
	"INGAME_RULE_CANNOT_PLAY_ON_DECK": "Cannot play on a deck",
	"INGAME_RULE_CANNOT_PLAY_ON_HAND": "Cannot play on the hand",
	"INGAME_RULE_CANNOT_PLAY_ON_DRAWPILE": "Cannot play on the draw pile",
	"INGAME_RULE_OPPONENT_SLOT_FORBIDDEN": "Opponent slot forbidden",

	"INGAME_TURN_START_FIRST": "You start",
	"INGAME_TURN_START": "Your turn",
	"INGAME_TURN_TIMEOUT": "Time’s up",
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
	"revange": "Rematch",
	"back_lobby": "Back to lobby",
	"retry": "Reconnect",
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
