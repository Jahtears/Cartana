# infra/notification/MessageCatalog.gd
#
# Source unique pour la reconstruction locale des popups et messages UI.
# Le protocole réseau fournit uniquement des codes métier neutres.

extends RefCounted
class_name MessageCatalog

const Protocol = preload("res://net/Protocol.gd")

const ERROR_CODE_TO_POPUP := {
  Protocol.WIRE_ERROR_TECHNICAL_ERROR:                Protocol.POPUP_TECH_ERROR_GENERIC,
  Protocol.WIRE_ERROR_BAD_REQUEST:                    Protocol.POPUP_TECH_BAD_REQUEST,
  Protocol.WIRE_ERROR_NOT_FOUND:                      Protocol.POPUP_TECH_NOT_FOUND,
  Protocol.WIRE_ERROR_FORBIDDEN:                      Protocol.POPUP_TECH_FORBIDDEN,
  Protocol.WIRE_ERROR_BAD_STATE:                      Protocol.POPUP_TECH_BAD_STATE,
  Protocol.WIRE_ERROR_NOT_IMPLEMENTED:                Protocol.POPUP_TECH_NOT_IMPLEMENTED,
  Protocol.WIRE_ERROR_INTERNAL_ERROR:                 Protocol.POPUP_TECH_INTERNAL_ERROR,
  Protocol.WIRE_ERROR_AUTH_REQUIRED:                  Protocol.POPUP_AUTH_REQUIRED,
  Protocol.WIRE_ERROR_AUTH_MISSING_CREDENTIALS:       Protocol.POPUP_AUTH_MISSING_CREDENTIALS,
  Protocol.WIRE_ERROR_AUTH_ALREADY_CONNECTED:         Protocol.POPUP_AUTH_ALREADY_CONNECTED,
  Protocol.WIRE_ERROR_AUTH_BAD_PIN:                   Protocol.POPUP_AUTH_BAD_PIN,
  Protocol.WIRE_ERROR_AUTH_RATE_LIMITED:              Protocol.POPUP_AUTH_MAX_TRY,
  Protocol.WIRE_ERROR_INVITE_TARGET_ALREADY_INVITED:  Protocol.POPUP_INVITE_TARGET_ALREADY_INVITED,
  Protocol.WIRE_ERROR_INVITE_TARGET_ALREADY_INVITING: Protocol.POPUP_INVITE_TARGET_ALREADY_INVITING,
  Protocol.WIRE_ERROR_INVITE_ACTOR_ALREADY_INVITED:   Protocol.POPUP_INVITE_ACTOR_ALREADY_INVITED,
  Protocol.WIRE_ERROR_INVITE_ACTOR_ALREADY_INVITING:  Protocol.POPUP_INVITE_ACTOR_ALREADY_INVITING,
  Protocol.WIRE_ERROR_INVITE_NOT_FOUND:               Protocol.POPUP_INVITE_NOT_FOUND,
  Protocol.WIRE_ERROR_GAME_PAUSED:                    Protocol.POPUP_GAME_PAUSED,
  Protocol.WIRE_ERROR_GAME_ENDED:                     Protocol.POPUP_GAME_ENDED,
  Protocol.WIRE_ERROR_INVALID_CLIENT_SLOT:            Protocol.POPUP_UI_ACTION_IMPOSSIBLE,
  Protocol.WIRE_ERROR_MOVE_DENIED:                    Protocol.POPUP_UI_ACTION_IMPOSSIBLE,
  Protocol.WIRE_ERROR_DECK_TO_TABLE_ONLY:             Protocol.POPUP_UI_ACTION_IMPOSSIBLE,
  Protocol.WIRE_ERROR_NOT_YOUR_TURN:                  Protocol.POPUP_UI_ACTION_IMPOSSIBLE,
  Protocol.WIRE_ERROR_BENCH_TO_TABLE_ONLY:            Protocol.POPUP_UI_ACTION_IMPOSSIBLE,
  Protocol.WIRE_ERROR_ACE_ON_DECK:                    Protocol.POPUP_UI_ACTION_IMPOSSIBLE,
  Protocol.WIRE_ERROR_ACE_IN_HAND:                    Protocol.POPUP_UI_ACTION_IMPOSSIBLE,
  Protocol.WIRE_ERROR_ALLOWED_ON_TABLE_ONLY:          Protocol.POPUP_UI_ACTION_IMPOSSIBLE,
  Protocol.WIRE_ERROR_OPPONENT_SLOT_FORBIDDEN:        Protocol.POPUP_UI_ACTION_IMPOSSIBLE,
  Protocol.WIRE_ERROR_TURN_TIMEOUT:                   Protocol.POPUP_UI_ACTION_IMPOSSIBLE,
}


# ══════════════════════════════════════════════════════════
# NORMALISATION POPUP
# ══════════════════════════════════════════════════════════

static func normalize_popup_message(payload: Dictionary) -> Dictionary:
  var params := _extract_popup_params(payload)
  var msg_code := _extract_popup_code(payload)
  var text_override := _extract_text(payload)

  if not msg_code.begins_with(Protocol.POPUP_PREFIX):
    msg_code = Protocol.POPUP_TECH_ERROR_GENERIC

  var text := text_override
  if text == "" or text == msg_code:
    text = popup_text(msg_code, params)
  if text == "":
    text = popup_text(Protocol.POPUP_TECH_ERROR_GENERIC)

  var normalized := {
    "text": text,
    "message_code": msg_code,
    "message_params": params,
  }
  if text_override != "" and text_override != msg_code:
    normalized["text_override"] = text_override
  return normalized


static func normalize_popup_error(error: Dictionary, fallback_message := Protocol.DEFAULT_ERROR_FALLBACK) -> Dictionary:
  var error_code := String(error.get("code", "")).strip_edges()
  var popup_code := String(ERROR_CODE_TO_POPUP.get(error_code, "")).strip_edges()
  if popup_code == "":
    var fallback := String(fallback_message).strip_edges()
    popup_code = fallback if fallback.begins_with(Protocol.POPUP_PREFIX) else Protocol.POPUP_TECH_ERROR_GENERIC

  return normalize_popup_message({
    "message_code": popup_code,
    "message_params": _extract_error_params(error),
  })


# ══════════════════════════════════════════════════════════
# INVITATION
# ══════════════════════════════════════════════════════════

static func normalize_invite_response(data: Dictionary) -> Dictionary:
  if bool(data.get("accepted", false)):
    return {}

  var actor := String(data.get("from", "")).strip_edges()
  if actor == "":
    actor = LanguageManager.ui_text("UI_GENERIC_USER", "User")

  return normalize_popup_message({
    "message_code": Protocol.POPUP_INVITE_DECLINED,
    "message_params": {"actor": actor},
  })


static func invite_cancelled_payload(data: Dictionary) -> Dictionary:
  var user_name := String(data.get("name", "")).strip_edges()
  if user_name == "":
    user_name = LanguageManager.ui_text("UI_GENERIC_USER", "User")

  return normalize_popup_message({
    "message_code": Protocol.POPUP_INVITE_CANCELLED,
    "message_params": {"name": user_name},
  })


static func invite_action_request(action_id: String, payload: Dictionary) -> Dictionary:
  var flow := String(payload.get("flow", ""))
  if flow != Protocol.POPUP_FLOW_INVITE_REQUEST:
    return {}

  var from_user := String(payload.get("from", ""))
  if from_user == "":
    return {}

  var req: Dictionary = {"to": from_user}

  var context := String(payload.get("context", "")).strip_edges()
  var source_game_id := String(payload.get("source_game_id", "")).strip_edges()
  if context != "":
    req["context"] = context
  if source_game_id != "":
    req["source_game_id"] = source_game_id

  if action_id == Protocol.POPUP_ACTION_CONFIRM_YES:
    req["accepted"] = true
    return req
  if action_id == Protocol.POPUP_ACTION_CONFIRM_NO:
    req["accepted"] = false
    return req

  return {}


# ══════════════════════════════════════════════════════════
# FIN DE PARTIE
# ══════════════════════════════════════════════════════════

static func game_end_popup_message(data: Dictionary, username: String, is_spectator: bool) -> Dictionary:
  var winner := _safe_text(data.get("winner", ""))
  var reason := _safe_text(data.get("reason", "")).to_lower()
  if reason == "":
    reason = Protocol.GAME_END_REASON_ABANDON

  if is_spectator:
    return {
      "message_code": _game_end_code_from_reason(reason),
      "message_params": {"name": winner if winner != "" else "-"},
    }

  if reason == Protocol.GAME_END_REASON_PILE_EMPTY or winner == "":
    return {
      "message_code": Protocol.POPUP_GAME_END_DRAW,
      "message_params": {},
    }

  if winner == _safe_text(username):
    return {
      "message_code": Protocol.POPUP_GAME_END_VICTORY,
      "message_params": {},
    }

  return {
    "message_code": Protocol.POPUP_GAME_END_DEFEAT,
    "message_params": {},
  }


# ══════════════════════════════════════════════════════════
# TRADUCTION
# ══════════════════════════════════════════════════════════

static func popup_text(message_code: String, params: Dictionary = {}) -> String:
  return LanguageManager.popup_text(message_code, params)


static func popup_label(label_key: String) -> String:
  return LanguageManager.label(label_key, label_key)


# ══════════════════════════════════════════════════════════
# HELPERS PRIVÉS
# ══════════════════════════════════════════════════════════

static func _game_end_code_from_reason(reason: String) -> String:
  match reason:
    Protocol.GAME_END_REASON_ABANDON: return Protocol.POPUP_GAME_END_ABANDON
    Protocol.GAME_END_REASON_DECK_EMPTY: return Protocol.POPUP_GAME_END_DECK_EMPTY
    Protocol.GAME_END_REASON_PILE_EMPTY: return Protocol.POPUP_GAME_END_PILE_EMPTY
    Protocol.GAME_END_REASON_TIMEOUT_STREAK: return Protocol.POPUP_GAME_END_TIMEOUT_STREAK
    _: return Protocol.POPUP_GAME_ENDED


static func _safe_text(value: Variant) -> String:
  if value == null:
    return ""
  return str(value).strip_edges()


static func _extract_error_params(error: Dictionary) -> Dictionary:
  var params_val = error.get("params", {})
  return params_val if params_val is Dictionary else {}


static func _extract_popup_params(payload: Dictionary) -> Dictionary:
  var params_val = payload.get("message_params", {})
  return params_val if params_val is Dictionary else {}


static func _extract_popup_code(payload: Dictionary) -> String:
  return String(payload.get("message_code", "")).strip_edges()


static func _extract_text(payload: Dictionary) -> String:
  return String(payload.get("text", "")).strip_edges()
