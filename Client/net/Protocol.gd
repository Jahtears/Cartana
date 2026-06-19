# Protocol.gd
# Constantes réseau et UI uniquement.
# Toute logique de construction / normalisation → MessageCatalog.gd
extends Node

const POPUP_PREFIX := "POPUP_"

const POPUP_TECH_ERROR_GENERIC    := "POPUP_TECH_ERROR_GENERIC"
const POPUP_TECH_BAD_REQUEST      := "POPUP_TECH_BAD_REQUEST"
const POPUP_TECH_NOT_FOUND        := "POPUP_TECH_NOT_FOUND"
const POPUP_TECH_FORBIDDEN        := "POPUP_TECH_FORBIDDEN"
const POPUP_TECH_BAD_STATE        := "POPUP_TECH_BAD_STATE"
const POPUP_TECH_NOT_IMPLEMENTED  := "POPUP_TECH_NOT_IMPLEMENTED"
const POPUP_TECH_INTERNAL_ERROR   := "POPUP_TECH_INTERNAL_ERROR"

const POPUP_AUTH_REQUIRED              := "POPUP_AUTH_REQUIRED"
const POPUP_AUTH_INVALID_USERNAME_MIN  := "POPUP_AUTH_INVALID_USERNAME_MIN"
const POPUP_AUTH_INVALID_PIN_MIN       := "POPUP_AUTH_INVALID_PIN_MIN"
const POPUP_AUTH_BAD_PIN               := "POPUP_AUTH_BAD_PIN"
const POPUP_AUTH_MAX_TRY               := "POPUP_AUTH_MAX_TRY"
const POPUP_AUTH_ALREADY_CONNECTED     := "POPUP_AUTH_ALREADY_CONNECTED"
const POPUP_AUTH_MISSING_CREDENTIALS   := "POPUP_AUTH_MISSING_CREDENTIALS"
const POPUP_AUTH_CONNECTION_ERROR      := "POPUP_AUTH_CONNECTION_ERROR"
const POPUP_PLAYER_DISCONNECTED        := "POPUP_PLAYER_DISCONNECTED"
const POPUP_PLAYER_RECONNECTED         := "POPUP_PLAYER_RECONNECTED"
const POPUP_PLAYER_RECONNECT_FAIL      := "POPUP_PLAYER_RECONNECT_FAIL"

const POPUP_INVITE_NOT_FOUND               := "POPUP_INVITE_NOT_FOUND"
const POPUP_INVITE_DECLINED                := "POPUP_INVITE_DECLINED"
const POPUP_INVITE_RECEIVED                := "POPUP_INVITE_RECEIVED"
const POPUP_INVITE_SENT                    := "POPUP_INVITE_SENT"
const POPUP_INVITE_FAILED                  := "POPUP_INVITE_FAILED"
const POPUP_INVITE_CANCELLED               := "POPUP_INVITE_CANCELLED"
const POPUP_INVITE_TARGET_ALREADY_INVITED  := "POPUP_INVITE_TARGET_ALREADY_INVITED"
const POPUP_INVITE_TARGET_ALREADY_INVITING := "POPUP_INVITE_TARGET_ALREADY_INVITING"
const POPUP_INVITE_ACTOR_ALREADY_INVITED   := "POPUP_INVITE_ACTOR_ALREADY_INVITED"
const POPUP_INVITE_ACTOR_ALREADY_INVITING  := "POPUP_INVITE_ACTOR_ALREADY_INVITING"

const POPUP_GAME_PAUSED         := "POPUP_GAME_PAUSED"
const POPUP_GAME_ENDED          := "POPUP_GAME_ENDED"
const POPUP_GAME_END_VICTORY    := "POPUP_GAME_END_VICTORY"
const POPUP_GAME_END_DEFEAT     := "POPUP_GAME_END_DEFEAT"
const POPUP_GAME_END_DRAW       := "POPUP_GAME_END_DRAW"
const POPUP_GAME_END_ABANDON    := "POPUP_GAME_END_ABANDON"
const POPUP_GAME_END_DECK_EMPTY := "POPUP_GAME_END_DECK_EMPTY"
const POPUP_GAME_END_PILE_EMPTY := "POPUP_GAME_END_PILE_EMPTY"
const POPUP_GAME_END_TIMEOUT_STREAK := "POPUP_GAME_END_TIMEOUT_STREAK"

const GAME_END_REASON_ABANDON        := "abandon"
const GAME_END_REASON_DECK_EMPTY     := "deck_empty"
const GAME_END_REASON_PILE_EMPTY     := "pile_empty"
const GAME_END_REASON_TIMEOUT_STREAK := "timeout_streak"

const POPUP_UI_ACTION_IMPOSSIBLE   := "POPUP_UI_ACTION_IMPOSSIBLE"
const POPUP_LOBBY_GET_PLAYERS_ERROR := "POPUP_LOBBY_GET_PLAYERS_ERROR"
const POPUP_SPECTATE_CONFIRM       := "POPUP_SPECTATE_CONFIRM"
const POPUP_LOGOUT_CONFIRM         := "POPUP_LOGOUT_CONFIRM"
const POPUP_OPPONENT_DISCONNECTED  := "POPUP_OPPONENT_DISCONNECTED"
const POPUP_OPPONENT_REJOINED      := "POPUP_OPPONENT_REJOINED"
const POPUP_QUIT_CONFIRM           := "POPUP_QUIT_CONFIRM"
const POPUP_OPPONENT_DISCONNECTED_CHOICE := "POPUP_OPPONENT_DISCONNECTED_CHOICE"

const WIRE_ERROR_TECHNICAL_ERROR               := "technical_error"
const WIRE_ERROR_BAD_REQUEST                   := "bad_request"
const WIRE_ERROR_NOT_FOUND                     := "not_found"
const WIRE_ERROR_FORBIDDEN                     := "forbidden"
const WIRE_ERROR_BAD_STATE                     := "bad_state"
const WIRE_ERROR_NOT_IMPLEMENTED               := "not_implemented"
const WIRE_ERROR_INTERNAL_ERROR                := "internal_error"
const WIRE_ERROR_AUTH_REQUIRED                 := "auth_required"
const WIRE_ERROR_AUTH_MISSING_CREDENTIALS      := "auth_missing_credentials"
const WIRE_ERROR_AUTH_ALREADY_CONNECTED        := "auth_already_connected"
const WIRE_ERROR_AUTH_BAD_PIN                  := "auth_bad_pin"
const WIRE_ERROR_AUTH_RATE_LIMITED             := "auth_rate_limited"
const WIRE_ERROR_INVITE_TARGET_ALREADY_INVITED := "invite_target_already_invited"
const WIRE_ERROR_INVITE_TARGET_ALREADY_INVITING := "invite_target_already_inviting"
const WIRE_ERROR_INVITE_ACTOR_ALREADY_INVITED  := "invite_actor_already_invited"
const WIRE_ERROR_INVITE_ACTOR_ALREADY_INVITING := "invite_actor_already_inviting"
const WIRE_ERROR_INVITE_NOT_FOUND              := "invite_not_found"
const WIRE_ERROR_GAME_PAUSED                   := "game_paused"
const WIRE_ERROR_GAME_ENDED                    := "game_ended"
const WIRE_ERROR_INVALID_CLIENT_SLOT           := "invalid_client_slot"
const WIRE_ERROR_MOVE_DENIED                   := "move_denied"
const WIRE_ERROR_DECK_TO_TABLE_ONLY            := "deck_to_table_only"
const WIRE_ERROR_NOT_YOUR_TURN                 := "not_your_turn"
const WIRE_ERROR_BENCH_TO_TABLE_ONLY           := "bench_to_table_only"
const WIRE_ERROR_ACE_ON_DECK                   := "ace_on_deck"
const WIRE_ERROR_ACE_IN_HAND                   := "ace_in_hand"
const WIRE_ERROR_ALLOWED_ON_TABLE_ONLY         := "allowed_on_table_only"
const WIRE_ERROR_OPPONENT_SLOT_FORBIDDEN       := "opponent_slot_forbidden"
const WIRE_ERROR_TURN_TIMEOUT                  := "turn_timeout"

const WIRE_FEEDBACK_OK                       := "ok"
const WIRE_FEEDBACK_TURN_START_FIRST         := "turn_start_first"
const WIRE_FEEDBACK_TURN_START               := "turn_start"
const WIRE_FEEDBACK_TURN_TIMEOUT             := "turn_timeout"
const WIRE_FEEDBACK_MOVE_DENIED              := "move_denied"
const WIRE_FEEDBACK_DECK_TO_TABLE_ONLY       := "deck_to_table_only"
const WIRE_FEEDBACK_NOT_YOUR_TURN            := "not_your_turn"
const WIRE_FEEDBACK_BENCH_TO_TABLE_ONLY      := "bench_to_table_only"
const WIRE_FEEDBACK_ACE_ON_DECK              := "ace_on_deck"
const WIRE_FEEDBACK_ACE_IN_HAND              := "ace_in_hand"
const WIRE_FEEDBACK_ALLOWED_ON_TABLE_ONLY    := "allowed_on_table_only"
const WIRE_FEEDBACK_OPPONENT_SLOT_FORBIDDEN  := "opponent_slot_forbidden"

const DEFAULT_ERROR_FALLBACK := POPUP_UI_ACTION_IMPOSSIBLE

# ============= POPUP FLOW / ACTION IDs =============
const POPUP_FLOW_INVITE_REQUEST  := "invite_request"
const POPUP_ACTION_CONFIRM_YES   := "confirm_yes"
const POPUP_ACTION_CONFIRM_NO    := "confirm_no"
const POPUP_ACTION_INFO_OK       := "info_ok"

const POPUP_FLOW   := {"INVITE_REQUEST": POPUP_FLOW_INVITE_REQUEST}
const POPUP_ACTION := {
  "CONFIRM_YES": POPUP_ACTION_CONFIRM_YES,
  "CONFIRM_NO":  POPUP_ACTION_CONFIRM_NO,
  "INFO_OK":     POPUP_ACTION_INFO_OK,
}

# ============= REQUEST TYPES =============
const REQ_LOGIN           := "login"
const REQ_LOGOUT          := "logout"
const REQ_PING            := "ping"
const REQ_GET_PLAYERS     := "get_players"
const REQ_GET_LEADERBOARD := "get_leaderboard"
const REQ_INVITE          := "invite"
const REQ_INVITE_RESPONSE := "invite_response"
const REQ_JOIN_GAME       := "join_game"
const REQ_SPECTATE_GAME   := "spectate_game"
const REQ_LEAVE_GAME      := "leave_game"
const REQ_ACK_GAME_END    := "ack_game_end"
const REQ_MOVE_REQUEST    := "move_request"
const EVT_GAME_FEEDBACK   := "game_feedback"

# ============= POPUP ACTION IDs =============
const ACTION_NETWORK_RETRY           := "network_retry"
const ACTION_QUIT_CANCEL             := "quit_cancel"
const ACTION_QUIT_CONFIRM            := "quit_confirm"
const ACTION_PAUSE_WAIT              := "pause_wait"
const ACTION_PAUSE_LEAVE             := "pause_leave"
const ACTION_GAME_END_LEAVE          := "game_end_leave"
const ACTION_GAME_END_REMATCH        := "game_end_rematch"
const ACTION_REMATCH_DECLINED_LEAVE  := "rematch_declined_leave"

# ============= GAME CONTEXT =============
const REMATCH_CONTEXT        := "rematch"
const ACK_INTENT_REMATCH     := "rematch"
const UI_GAME_QUIT_BUTTON_KEY := "UI_GAME_QUIT_BUTTON"
