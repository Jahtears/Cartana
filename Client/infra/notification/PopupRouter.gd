# infra/notification/PopupRouter.gd
#
# Façade haut-niveau pour l'affichage de popups.
# Chaque méthode correspond à un cas métier précis.
#
# Avant (dans chaque appelant) :
#   var popup := PopupMessage.normalize_popup_error(error, Protocol.POPUP_INVITE_FAILED)
#   PopupUi.show_normalized(PopupUi.MODE_INFO, popup)
#
# Après :
#   PopupRouter.show_error(error, Protocol.POPUP_INVITE_FAILED)
#
# N'a pas d'état. Toutes les méthodes sont statiques.
# Appelle PopupUi (autoload → WindowPopup) et MessageCatalog.

extends RefCounted
class_name PopupRouter

const Protocol = preload("res://net/Protocol.gd")


# ══════════════════════════════════════════════════════════
# GÉNÉRIQUES
# ══════════════════════════════════════════════════════════

## Popup d'information simple — un seul bouton OK.
## options : clés optionnelles ok_action_id, ok_label_key.
static func show_info(message_code: String, params: Dictionary = {}, options: Dictionary = {}) -> void:
  PopupUi.show_code(PopupUi.MODE_INFO, message_code, params, {}, options)


## Popup d'erreur réseau normalisée — affiche le message traduit de l'erreur.
static func show_error(error: Dictionary, fallback: String = Protocol.DEFAULT_ERROR_FALLBACK) -> void:
  var normalized := MessageCatalog.normalize_popup_error(error, fallback)
  PopupUi.show_normalized(PopupUi.MODE_INFO, normalized)


# ══════════════════════════════════════════════════════════
# CONNEXION / RÉSEAU
# ══════════════════════════════════════════════════════════

## Connexion restaurée après perte réseau.
static func show_reconnected() -> void:
  PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_PLAYER_RECONNECTED)


## Reconnexion échouée — bouton Réessayer.
static func show_reconnect_failed() -> void:
  PopupUi.show_code(
    PopupUi.MODE_INFO,
    Protocol.POPUP_PLAYER_RECONNECT_FAIL,
    {}, {},
    {
      "ok_action_id": Protocol.ACTION_NETWORK_RETRY,
      "ok_label_key": "UI_LABEL_RETRY",
    }
  )


## Perte de connexion passive (sans action requise).
static func show_connection_lost() -> void:
  PopupUi.show_code(PopupUi.MODE_INFO, Protocol.POPUP_PLAYER_DISCONNECTED)


# ══════════════════════════════════════════════════════════
# INVITATION
# ══════════════════════════════════════════════════════════

## Invitation reçue d'un autre joueur — boutons Accepter / Refuser.
## context       : "" ou "rematch"
## source_game_id : renseigné pour les revanches
static func show_invite_received(from_user: String, context: String = "", source_game_id: String = "") -> void:
  var popup_payload := {
    "flow": Protocol.POPUP_FLOW_INVITE_REQUEST,
    "from": from_user,
  }
  if context != "":
    popup_payload["context"] = context
  if source_game_id != "":
    popup_payload["source_game_id"] = source_game_id

  PopupUi.show_code(
    PopupUi.MODE_CONFIRM,
    Protocol.POPUP_INVITE_RECEIVED,
    {"from": from_user},
    popup_payload,
    {
      "yes_label_key": "UI_LABEL_ACCEPT",
      "no_label_key":  "UI_LABEL_REFUSE",
    }
  )


## Réponse à une invitation (acceptée ou refusée par l'adversaire).
static func show_invite_response(data: Dictionary) -> void:
  var normalized := MessageCatalog.normalize_invite_response(data)
  if String(normalized.get("text", "")) != "":
    PopupUi.show_normalized(PopupUi.MODE_INFO, normalized)


## Invitation annulée — l'expéditeur est passé hors-ligne.
static func show_invite_cancelled(data: Dictionary) -> void:
  var normalized := MessageCatalog.invite_cancelled_payload(data)
  if String(normalized.get("text", "")).strip_edges() == "":
    return
  PopupUi.show_normalized(PopupUi.MODE_INFO, normalized)


## Revanche refusée — bouton Retour lobby.
static func show_rematch_declined(data: Dictionary) -> void:
  var rematch_ctx := String(data.get("context", "")).strip_edges().to_lower()
  if rematch_ctx != Protocol.REMATCH_CONTEXT:
    return
  var normalized := MessageCatalog.normalize_invite_response(data)
  PopupUi.show_normalized(
    PopupUi.MODE_INFO,
    normalized,
    {
      "context":        rematch_ctx,
      "source_game_id": String(data.get("source_game_id", "")).strip_edges(),
    }
  )


# ══════════════════════════════════════════════════════════
# LOBBY
# ══════════════════════════════════════════════════════════

## Confirmer l'observation d'une partie en spectateur.
static func show_spectate_confirm(game_id: String, players: Array) -> void:
  PopupUi.show_code(
    PopupUi.MODE_CONFIRM,
    Protocol.POPUP_SPECTATE_CONFIRM,
    {
      "game_id": game_id,
      "players": str(players),
    },
    {
      "flow":    Protocol.REQ_SPECTATE_GAME,
      "game_id": game_id,
    }
  )


## Confirmer la déconnexion et le retour à l'écran de login.
static func show_logout_confirm() -> void:
  PopupUi.show_code(
    PopupUi.MODE_CONFIRM,
    Protocol.POPUP_LOGOUT_CONFIRM,
    {}, {"flow": Protocol.REQ_LOGOUT}
  )


# ══════════════════════════════════════════════════════════
# EN PARTIE
# ══════════════════════════════════════════════════════════

## Confirmer le retour au lobby depuis une partie en cours.
static func show_quit_confirm() -> void:
  PopupUi.show_code(
    PopupUi.MODE_CONFIRM,
    Protocol.POPUP_QUIT_CONFIRM,
    {}, {},
    {
      "yes_action_id": Protocol.ACTION_QUIT_CANCEL,
      "no_action_id":  Protocol.ACTION_QUIT_CONFIRM,
      "yes_label_key": "UI_LABEL_CANCEL",
      "no_label_key":  "UI_LABEL_QUIT",
    }
  )


## Adversaire déconnecté : proposer d'attendre ou de revenir au lobby.
static func show_pause_disconnect_choice(opponent_name: String) -> void:
  PopupUi.show_code(
    PopupUi.MODE_CONFIRM,
    Protocol.POPUP_OPPONENT_DISCONNECTED_CHOICE,
    {"name": opponent_name},
    {},
    {
      "yes_action_id": Protocol.ACTION_PAUSE_WAIT,
      "no_action_id":  Protocol.ACTION_PAUSE_LEAVE,
      "yes_label_key": "UI_LABEL_WAIT",
      "no_label_key":  "UI_LABEL_BACK_LOBBY",
    }
  )


## Fin de partie : info seule (spectateur, ou pas de revanche possible).
static func show_game_end_info(data: Dictionary, username: String, game_id: String) -> void:
  var msg := MessageCatalog.game_end_popup_message(data, username, true)
  PopupUi.show_code(
    PopupUi.MODE_INFO,
    String(msg.get("message_code", "")),
    msg.get("message_params", {}) as Dictionary,
    {"game_id": game_id},
    {
      "ok_action_id": Protocol.ACTION_GAME_END_LEAVE,
      "ok_label_key": "UI_LABEL_BACK_LOBBY",
    }
  )


## Fin de partie : choix Retour lobby / Revanche.
static func show_game_end_with_rematch(data: Dictionary, username: String, game_id: String) -> void:
  var msg := MessageCatalog.game_end_popup_message(data, username, false)
  PopupUi.show_code(
    PopupUi.MODE_CONFIRM,
    String(msg.get("message_code", "")),
    msg.get("message_params", {}) as Dictionary,
    {"game_id": game_id},
    {
      "yes_action_id": Protocol.ACTION_GAME_END_LEAVE,
      "no_action_id":  Protocol.ACTION_GAME_END_REMATCH,
      "yes_label_key": "UI_LABEL_BACK_LOBBY",
      "no_label_key":  "UI_LABEL_REMATCH",
    }
  )


## Point d'entrée unique pour la fin de partie — choisit automatiquement
## entre info seule et choix de revanche.
## is_spectator       : force le mode info (spectateur ne peut pas faire de revanche)
## rematch_allowed    : false si l'adversaire est déconnecté ou indisponible
static func show_game_end(
  data: Dictionary,
  username: String,
  is_spectator: bool,
  rematch_allowed: bool,
  game_id: String
) -> void:
  if is_spectator or not rematch_allowed:
    show_game_end_info(data, username, game_id)
  else:
    show_game_end_with_rematch(data, username, game_id)
