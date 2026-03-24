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

# ============= REQUEST TYPES =============

const REQ_LOGIN            := "login"
const REQ_LOGOUT           := "logout"
const REQ_PING             := "ping"
const REQ_GET_PLAYERS      := "get_players"
const REQ_GET_LEADERBOARD  := "get_leaderboard"
const REQ_INVITE           := "invite"
const REQ_INVITE_RESPONSE  := "invite_response"
const REQ_JOIN_GAME        := "join_game"
const REQ_SPECTATE_GAME    := "spectate_game"
const REQ_LEAVE_GAME       := "leave_game"
const REQ_ACK_GAME_END     := "ack_game_end"
const REQ_MOVE_REQUEST     := "move_request"

# ============= POPUP ACTION IDs =============

const ACTION_NETWORK_RETRY        := "network_retry"
const ACTION_QUIT_CANCEL          := "quit_cancel"
const ACTION_QUIT_CONFIRM         := "quit_confirm"
const ACTION_PAUSE_WAIT           := "pause_wait"
const ACTION_PAUSE_LEAVE          := "pause_leave"
const ACTION_GAME_END_LEAVE       := "game_end_leave"
const ACTION_GAME_END_REMATCH     := "game_end_rematch"
const ACTION_REMATCH_DECLINED_LEAVE := "rematch_declined_leave"

# ============= GAME CONTEXT =============

const REMATCH_CONTEXT        := "rematch"
const ACK_INTENT_REMATCH     := "rematch"
const UI_GAME_QUIT_BUTTON_KEY := "UI_GAME_QUIT_BUTTON"

# ============= HELPERS =============

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
