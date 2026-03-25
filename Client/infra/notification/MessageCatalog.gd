# infra/notification/MessageCatalog.gd
#
# Source unique pour toute normalisation de message popup/règle.
# Remplace PopupMessage.gd.
#
# Responsabilités :
#   - Normaliser les payloads popup (erreurs réseau, fins de partie, invitations)
#   - Traduire les codes message via LanguageManager
#   - Construire les requêtes d'action d'invitation (déduplication Protocol.gd)
#
# N'affiche rien. N'appelle pas PopupUi.
# Pour afficher : utiliser PopupRouter.

extends RefCounted
class_name MessageCatalog

const Protocol = preload("res://net/Protocol.gd")

# ══════════════════════════════════════════════════════════
# NORMALISATION POPUP
# ══════════════════════════════════════════════════════════

## Normalise un payload brut en dictionnaire affichable.
## Garantit que text, message_code et message_params sont toujours présents.
static func normalize_popup_message(payload: Dictionary) -> Dictionary:
  var params    := _extract_message_params(payload)
  var msg_code  := _extract_message_code(payload)
  var text_ovrd := _extract_text(payload)

  if not msg_code.begins_with(Protocol.POPUP_PREFIX):
    if text_ovrd != "":
      msg_code = Protocol.POPUP_TECH_ERROR_GENERIC
    else:
      msg_code = Protocol.DEFAULT_ERROR_FALLBACK

  var text := text_ovrd
  if text == "" or text == msg_code:
    text = popup_text(msg_code, params)
  if text == "":
    text = popup_text(Protocol.POPUP_TECH_ERROR_GENERIC)

  var normalized := {
    "text":           text,
    "message_code":   msg_code,
    "message_params": params,
  }
  if text_ovrd != "" and text_ovrd != msg_code:
    normalized["text_override"] = text_ovrd
  return normalized


## Normalise une erreur réseau en payload affichable.
## fallback_message : code POPUP_* utilisé si error.message_code est absent.
static func normalize_popup_error(error: Dictionary, fallback_message := Protocol.DEFAULT_ERROR_FALLBACK) -> Dictionary:
  var top_params_val = error.get("message_params", {})
  var top_params: Dictionary = top_params_val if top_params_val is Dictionary else {}

  var msg_code   := String(error.get("message_code", "")).strip_edges()
  var text_ovrd  := String(error.get("text", "")).strip_edges()
  var fallback   := String(fallback_message).strip_edges()

  if msg_code == "":
    if fallback.begins_with(Protocol.POPUP_PREFIX):
      msg_code = fallback
    else:
      msg_code = Protocol.POPUP_TECH_ERROR_GENERIC
      if text_ovrd == "":
        text_ovrd = fallback

  if not msg_code.begins_with(Protocol.POPUP_PREFIX):
    if text_ovrd == "":
      text_ovrd = msg_code
    msg_code = Protocol.POPUP_TECH_ERROR_GENERIC

  return normalize_popup_message({
    "message_code":   msg_code,
    "message_params": top_params,
    "text":           text_ovrd,
  })


# ══════════════════════════════════════════════════════════
# INVITATION
# ══════════════════════════════════════════════════════════

## Normalise la réponse à une invitation (acceptée/refusée) en payload affichable.
static func normalize_invite_response(data: Dictionary) -> Dictionary:
  var ui_val = data.get("ui", {})
  var ui: Dictionary = ui_val if ui_val is Dictionary else {}
  return normalize_popup_message(ui)


## Construit le payload "invitation annulée" (joueur passé hors-ligne).
static func invite_cancelled_payload(data: Dictionary) -> Dictionary:
  var user_name := String(data.get("name", "")).strip_edges()
  if user_name == "":
    user_name = LanguageManager.ui_text("UI_GENERIC_USER", "User")

  return normalize_popup_message({
    "message_code":   Protocol.POPUP_INVITE_CANCELLED,
    "message_params": {"name": user_name},
  })


## Construit la requête réseau (invite_response) à partir d'une action popup.
## Retourne {} si l'action ou le payload ne correspondent pas à un flow d'invitation.
## Source unique — Protocol.gd ne doit plus contenir cette logique.
static func invite_action_request(action_id: String, payload: Dictionary) -> Dictionary:
  var flow := String(payload.get("flow", ""))
  if flow != Protocol.POPUP_FLOW_INVITE_REQUEST:
    return {}

  var from_user := String(payload.get("from", ""))
  if from_user == "":
    return {}

  var req: Dictionary = {}
  req["to"] = from_user

  var context       := String(payload.get("context", "")).strip_edges()
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

## Construit le payload popup de fin de partie (victoire, défaite, nul, abandon…).
## username     : le joueur local (pour déterminer victoire vs défaite)
## is_spectator : affiche le résultat objectif (gagnant) au lieu de victoire/défaite
static func game_end_popup_message(data: Dictionary, username: String, is_spectator: bool) -> Dictionary:
  var winner := _safe_text(data.get("winner", ""))
  var reason := _safe_text(data.get("reason", "")).to_lower()
  if reason == "":
    reason = Protocol.GAME_END_REASON_ABANDON

  if is_spectator:
    return {
      "message_code":   _game_end_code_from_reason(reason),
      "message_params": {"name": winner if winner != "" else "-"},
    }

  if reason == Protocol.GAME_END_REASON_PILE_EMPTY or winner == "":
    return {
      "message_code":   Protocol.POPUP_GAME_END_DRAW,
      "message_params": {},
    }

  if winner == _safe_text(username):
    return {
      "message_code":   Protocol.POPUP_GAME_END_VICTORY,
      "message_params": {},
    }

  return {
    "message_code":   Protocol.POPUP_GAME_END_DEFEAT,
    "message_params": {},
  }


# ══════════════════════════════════════════════════════════
# TRADUCTION
# ══════════════════════════════════════════════════════════

## Traduit un code POPUP_* en texte localisé.
static func popup_text(message_code: String, params: Dictionary = {}) -> String:
  return LanguageManager.popup_text(message_code, params)


## Traduit une clé de label UI (bouton OK, Oui, Non…).
static func popup_label(label_key: String) -> String:
  return LanguageManager.label(label_key, label_key)


# ══════════════════════════════════════════════════════════
# HELPERS PRIVÉS
# ══════════════════════════════════════════════════════════

static func _game_end_code_from_reason(reason: String) -> String:
  match reason:
    Protocol.GAME_END_REASON_ABANDON:        return Protocol.POPUP_GAME_END_ABANDON
    Protocol.GAME_END_REASON_DECK_EMPTY:     return Protocol.POPUP_GAME_END_DECK_EMPTY
    Protocol.GAME_END_REASON_PILE_EMPTY:     return Protocol.POPUP_GAME_END_PILE_EMPTY
    Protocol.GAME_END_REASON_TIMEOUT_STREAK: return Protocol.POPUP_GAME_END_TIMEOUT_STREAK
    _:                                        return Protocol.POPUP_GAME_ENDED


static func _safe_text(value: Variant) -> String:
  if value == null:
    return ""
  return str(value).strip_edges()


static func _extract_message_params(payload: Dictionary) -> Dictionary:
  var val = payload.get("message_params", {})
  return val if val is Dictionary else {}


static func _extract_message_code(payload: Dictionary) -> String:
  return String(payload.get("message_code", "")).strip_edges()


static func _extract_text(payload: Dictionary) -> String:
  return String(payload.get("text", "")).strip_edges()
