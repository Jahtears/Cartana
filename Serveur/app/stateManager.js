// app/stateManager.js - Gestionnaire d'état centralisé

export class StateManager {
  constructor() {
    // Game state
    this.games = new Map();           // game_id → game object
    this.gameMeta = new Map();        // game_id → meta (slot_sig, turn_sig, etc)
    this.gameSpectators = new Map();  // game_id → Set<username>

    // User state
    this.wsByUser = new Map();        // username → ws
    this.userByWs = new Map();        // ws → username
    this.userToGame = new Map();      // username → game_id (en train de jouer)
    this.userToSpectate = new Map();  // username → game_id (en train de spectater)

    // Temporary state
    this.readyPlayers = new Map();    // username → is_ready flag
    this.pendingInviteTo = new Map(); // username → {from, to, accepted}
    this.inviteFrom = new Map();      // username(from) → username(to)
  }

  // ========================
  // GAMES — opérations composées uniquement
  // ========================

  /** Supprime une partie et toutes ses données associées */
  deleteGame(game_id) {
    this.games.delete(game_id);
    this.gameMeta.delete(game_id);
    this.gameSpectators.delete(game_id);
  }

  // ========================
  // SPECTATORS — Set imbriqué dans une Map
  // ========================

  addGameSpectator(game_id, username) {
    if (!this.gameSpectators.has(game_id)) {
      this.gameSpectators.set(game_id, new Set());
    }
    this.gameSpectators.get(game_id).add(username);
  }

  removeGameSpectator(game_id, username) {
    this.gameSpectators.get(game_id)?.delete(username);
  }

  getGameSpectators(game_id) {
    const s = this.gameSpectators.get(game_id);
    return s ? Array.from(s) : [];
  }

  // ========================
  // WEBSOCKETS — sync double-map
  // ========================

  registerUser(username, ws) {
    this.wsByUser.set(username, ws);
    this.userByWs.set(ws, username);
  }

  unregisterUser(username, ws) {
    this.wsByUser.delete(username);
    this.userByWs.delete(ws);
  }

  getWS(username)      { return this.wsByUser.get(username); }
  getUsername(ws)      { return this.userByWs.get(ws); }

  // ========================
  // UTILITIES
  // ========================

  /** Retourne les joueurs actuellement dans une partie */
  getGameUsers(game_id) {
    const users = [];
    for (const [username, gid] of this.userToGame) {
      if (gid === game_id) users.push(username);
    }
    return users;
  }

  /** Nettoie complètement un utilisateur (déconnexion) */
  cleanupUser(username) {
    const ws = this.wsByUser.get(username);
    this.wsByUser.delete(username);
    if (ws) this.userByWs.delete(ws);
    this.userToGame.delete(username);
    this.userToSpectate.delete(username);
    this.readyPlayers.delete(username);

    const invToMe = this.pendingInviteTo.get(username);
    if (invToMe?.from) this.inviteFrom.delete(invToMe.from);
    this.pendingInviteTo.delete(username);

    const invitedTo = this.inviteFrom.get(username);
    if (invitedTo) this.pendingInviteTo.delete(invitedTo);
    this.inviteFrom.delete(username);
  }

  /** Snapshot pour debug/monitoring */
  getSnapshot() {
    return {
      games_count:      this.games.size,
      users_count:      this.wsByUser.size,
      users_in_game:    this.userToGame.size,
      users_spectating: this.userToSpectate.size,
      ready_players:    this.readyPlayers.size,
      pending_invites:  this.pendingInviteTo.size,
      pending_invites_from: this.inviteFrom.size,
    };
  }
}

export function createStateManager() {
  return new StateManager();
}
