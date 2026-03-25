# infra/network/ClientAPI.gd
#
# Façade unique pour toute la communication réseau client.
# Enregistrer dans project.godot > Autoload sous le nom "ClientAPI"
# APRÈS NetworkManager.
#
# Contrat :
#   - Les scènes n'appellent plus NetworkManager directement.
#   - Toutes les requêtes sortantes passent par des méthodes typées.
#   - Toutes les réponses et événements serveur arrivent via des signaux typés.
#
# NetworkManager reste le transport bas niveau (WebSocket, reconnexion, timeouts).
# ClientAPI est le contrat métier au-dessus.

extends Node

# ══════════════════════════════════════════════════════════
# SIGNAUX — CONNEXION
# ══════════════════════════════════════════════════════════

signal connection_lost()
signal connection_restored()
signal reconnect_failed()
## reason = raison lisible, code = code WebSocket (1000, 1006, …)
signal server_closed(reason: String, code: int)
## Émis à chaque déconnexion (volontaire ou non). Utile pour Login.gd.
signal disconnected(code: int, reason: String)


# ══════════════════════════════════════════════════════════
# SIGNAUX — RÉPONSES (client → serveur → réponse)
# ══════════════════════════════════════════════════════════

# --- Auth ---
signal login_ok(username: String, status: Dictionary)
signal login_failed(error: Dictionary)
signal logout_ok()

# --- Lobby ---
signal players_list_ok(players: Array, statuses: Dictionary, games: Array)
signal players_list_failed(error: Dictionary)
signal leaderboard_ok(rows: Array)
signal leaderboard_failed(error: Dictionary)
signal invite_sent()
signal invite_send_failed(error: Dictionary)
signal invite_responded()
signal invite_respond_failed(error: Dictionary)

# --- Partie ---
signal join_game_ok(data: Dictionary)
signal join_game_failed(error: Dictionary)
signal spectate_ok(data: Dictionary)
signal spectate_failed(error: Dictionary)
signal leave_game_ok(game_id: String)
signal ack_game_end_ok(game_id: String)
signal move_ok(data: Dictionary)
signal move_failed(error: Dictionary)


# ══════════════════════════════════════════════════════════
# SIGNAUX — ÉVÉNEMENTS SERVEUR (push)
# ══════════════════════════════════════════════════════════

# --- Auth / session ---
signal evt_start_game(game_id: String, players: Array, spectator: bool)

# --- Board ---
signal evt_state_snapshot(data: Dictionary)
signal evt_slot_state(slot_id: String, cards: Array, count: int)
signal evt_table_sync(slots: Array)

# --- Tour ---
signal evt_turn_update(data: Dictionary)

# --- Fin de partie ---
signal evt_game_end(data: Dictionary)

# --- Message in-game (RULE_*) ---
signal evt_game_message(message_code: String, message_params: Dictionary)

# --- Adversaire ---
signal evt_opponent_disconnected(game_id: String, username: String)
signal evt_opponent_rejoined(game_id: String, username: String)

# --- Invitation ---
signal evt_invite_received(from: String, context: String, source_game_id: String)
signal evt_invite_response(data: Dictionary)
signal evt_invite_cancelled(data: Dictionary)
signal evt_rematch_declined(data: Dictionary)

# --- Lobby push ---
signal evt_players_updated(players: Array, statuses: Dictionary)
signal evt_games_updated(games: Array)


# ══════════════════════════════════════════════════════════
# LIFECYCLE
# ══════════════════════════════════════════════════════════

func _ready() -> void:
  NetworkManager.response.connect(_on_response)
  NetworkManager.evt.connect(_on_evt)
  NetworkManager.disconnected.connect(_on_disconnected)
  NetworkManager.connection_lost.connect(_on_connection_lost)
  NetworkManager.connection_restored.connect(_on_connection_restored)
  NetworkManager.reconnect_failed.connect(_on_reconnect_failed)
  NetworkManager.server_closed.connect(_on_server_closed)


# ══════════════════════════════════════════════════════════
# MÉTHODES SORTANTES — CONNEXION
# ══════════════════════════════════════════════════════════

## Ouvre la connexion WebSocket. Appeler au démarrage de Login.
func connect_to_server() -> void:
  NetworkManager.connect_to_server()

## Ferme proprement la connexion (déconnexion volontaire).
func close(code: int = 1000, reason: String = "") -> void:
  NetworkManager.close(code, reason)

## Force une tentative de reconnexion immédiate (bouton "Réessayer").
func retry_connection() -> void:
  NetworkManager.retry_now()

## Vrai si le WebSocket est ouvert et prêt.
func is_online() -> bool:
  return NetworkManager.is_open()

## Horloge serveur synchronisée en millisecondes epoch.
func server_now_ms() -> int:
  return NetworkManager.server_now_ms()

## Synchronise le décalage d'horloge avec le serveur.
func sync_server_clock(server_epoch_ms: int) -> void:
  NetworkManager.sync_server_clock(server_epoch_ms)


# ══════════════════════════════════════════════════════════
# MÉTHODES SORTANTES — AUTH
# ══════════════════════════════════════════════════════════

## Connexion avec identifiant + PIN.
## Réponse → login_ok / login_failed
func login(username: String, pin: String) -> void:
  NetworkManager.request("login", {
    "username": username.strip_edges(),
    "pin":      pin.strip_edges(),
  })

## Déconnexion — attend la confirmation serveur avant de retourner.
func logout() -> void:
  await NetworkManager.request_async("logout", {}, 3.0)
  NetworkManager.close(1000, NetworkManager.DISCONNECT_REASON_LOGOUT)


# ══════════════════════════════════════════════════════════
# MÉTHODES SORTANTES — LOBBY
# ══════════════════════════════════════════════════════════

## Demande la liste des joueurs et des parties en cours.
## Réponse → players_list_ok / players_list_failed
func get_players() -> void:
  NetworkManager.request("get_players", {})

## Demande le classement.
## Réponse → leaderboard_ok / leaderboard_failed
func get_leaderboard() -> void:
  NetworkManager.request("get_leaderboard", {})

## Envoie une invitation à jouer.
## context       : "" ou "rematch"
## source_game_id : renseigné pour une revanche
## Réponse → invite_sent / invite_send_failed
func send_invite(to: String, context: String = "", source_game_id: String = "") -> void:
  var payload: Dictionary = {"to": to}
  if context != "":
    payload["context"] = context
  if source_game_id != "":
    payload["source_game_id"] = source_game_id
  NetworkManager.request("invite", payload)

## Répond à une invitation reçue (accepter ou refuser).
## Réponse → invite_responded / invite_respond_failed
func respond_to_invite(
  to: String,
  accepted: bool,
  context: String = "",
  source_game_id: String = ""
) -> void:
  var payload: Dictionary = {"to": to, "accepted": accepted}
  if context != "":
    payload["context"] = context
  if source_game_id != "":
    payload["source_game_id"] = source_game_id
  NetworkManager.request("invite_response", payload)


# ══════════════════════════════════════════════════════════
# MÉTHODES SORTANTES — PARTIE
# ══════════════════════════════════════════════════════════

## Rejoint une partie comme joueur.
## Réponse → join_game_ok / join_game_failed
func join_game(game_id: String) -> void:
  NetworkManager.request("join_game", {"game_id": game_id})

## Rejoint une partie comme spectateur.
## Réponse → spectate_ok / spectate_failed
func spectate_game(game_id: String) -> void:
  NetworkManager.request("spectate_game", {"game_id": game_id})

## Quitte la partie en cours (abandon → l'adversaire gagne).
## Réponse → leave_game_ok
func leave_game(game_id: String) -> void:
  NetworkManager.request("leave_game", {"game_id": game_id})

## Acquitte la fin de partie.
## intent : "" (retour lobby) ou "rematch" (intention de revanche)
## Réponse via retour direct (await) → Dictionary {ok, game_id, …}
func ack_game_end(game_id: String, intent: String = "") -> Dictionary:
  var payload: Dictionary = {"game_id": game_id}
  if intent != "":
    payload["intent"] = intent
  return await NetworkManager.request_async("ack_game_end", payload, 6.0)

## Envoie un mouvement de carte.
## Réponse → move_ok / move_failed
func move_card(card_id: String, from_slot_id: String, to_slot_id: String) -> void:
  NetworkManager.request("move_request", {
    "card_id":      card_id,
    "from_slot_id": from_slot_id,
    "to_slot_id":   to_slot_id,
  })

## Ping serveur (utilisé pour mesurer la latence ou vérifier la connexion).
func ping() -> void:
  NetworkManager.request("ping", {})


# ══════════════════════════════════════════════════════════
# ROUTING INTERNE — RÉPONSES
# ══════════════════════════════════════════════════════════

func _on_response(_rid: String, type: String, ok: bool, data: Dictionary, error: Dictionary) -> void:
  match type:
    # --- Auth ---
    "login":
      if ok:
        login_ok.emit(
          String(data.get("username", "")),
          data.get("status", {}) as Dictionary
        )
      else:
        login_failed.emit(error)

    "logout":
      if ok:
        logout_ok.emit()

    # --- Lobby ---
    "get_players":
      if ok:
        players_list_ok.emit(
          _coerce_array(data.get("players", [])),
          _coerce_dict(data.get("statuses", {})),
          _coerce_array(data.get("games", []))
        )
      else:
        players_list_failed.emit(error)

    "get_leaderboard":
      if ok:
        leaderboard_ok.emit(_coerce_array(data.get("leaderboard", [])))
      else:
        leaderboard_failed.emit(error)

    "invite":
      if ok:
        invite_sent.emit()
      else:
        invite_send_failed.emit(error)

    "invite_response":
      if ok:
        invite_responded.emit()
      else:
        invite_respond_failed.emit(error)

    # --- Partie ---
    "join_game":
      if ok:
        join_game_ok.emit(data)
      else:
        join_game_failed.emit(error)

    "spectate_game":
      if ok:
        spectate_ok.emit(data)
      else:
        spectate_failed.emit(error)

    "leave_game":
      if ok:
        leave_game_ok.emit(String(data.get("game_id", "")))

    "ack_game_end":
      if ok:
        ack_game_end_ok.emit(String(data.get("game_id", "")))

    "move_request":
      if ok:
        move_ok.emit(data)
      else:
        move_failed.emit(error)


# ══════════════════════════════════════════════════════════
# ROUTING INTERNE — ÉVÉNEMENTS SERVEUR
# ══════════════════════════════════════════════════════════

func _on_evt(type: String, data: Dictionary) -> void:
  match type:
    "start_game":
      evt_start_game.emit(
        String(data.get("game_id", "")),
        _coerce_array(data.get("players", [])),
        bool(data.get("spectator", false))
      )

    "state_snapshot":
      evt_state_snapshot.emit(data)

    "slot_state":
      evt_slot_state.emit(
        String(data.get("slot_id", "")),
        _coerce_array(data.get("cards", [])),
        int(data.get("count", 0))
      )

    "table_sync":
      evt_table_sync.emit(_coerce_array(data.get("slots", [])))

    "turn_update":
      evt_turn_update.emit(data)

    "game_end":
      evt_game_end.emit(data)

    "show_game_message":
      evt_game_message.emit(
        String(data.get("message_code", "")),
        _coerce_dict(data.get("message_params", {}))
      )

    "opponent_disconnected":
      evt_opponent_disconnected.emit(
        String(data.get("game_id", "")),
        String(data.get("username", ""))
      )

    "opponent_rejoined":
      evt_opponent_rejoined.emit(
        String(data.get("game_id", "")),
        String(data.get("username", ""))
      )

    "invite_request":
      evt_invite_received.emit(
        String(data.get("from", "")),
        String(data.get("context", "")).strip_edges(),
        String(data.get("source_game_id", "")).strip_edges()
      )

    "invite_response":
      evt_invite_response.emit(data)

    "invite_cancelled":
      evt_invite_cancelled.emit(data)

    "rematch_declined":
      evt_rematch_declined.emit(data)

    "players_list":
      evt_players_updated.emit(
        _coerce_array(data.get("players", [])),
        _coerce_dict(data.get("statuses", {}))
      )

    "games_list":
      evt_games_updated.emit(_coerce_array(data.get("games", [])))


# ══════════════════════════════════════════════════════════
# ROUTING INTERNE — CONNEXION
# ══════════════════════════════════════════════════════════

func _on_disconnected(code: int, reason: String) -> void:
  disconnected.emit(code, reason)

func _on_connection_lost() -> void:
  connection_lost.emit()

func _on_connection_restored() -> void:
  connection_restored.emit()

func _on_reconnect_failed() -> void:
  reconnect_failed.emit()

func _on_server_closed(server_reason: String, close_code: int, _raw_reason: String) -> void:
  server_closed.emit(server_reason, close_code)


# ══════════════════════════════════════════════════════════
# UTILITAIRES PRIVÉS
# ══════════════════════════════════════════════════════════

static func _coerce_array(value: Variant) -> Array:
  return value if value is Array else []

static func _coerce_dict(value: Variant) -> Dictionary:
  return value if value is Dictionary else {}
