// app/stateManager.js - Gestionnaire d'état centralisé (maps singletons)

/**
 * StateManager centralise tout l'état du serveur
 * Responsabilités: mémoriser l'état, pas de logique métier
 */
export class StateManager {
  constructor() {
    // Game state
    this.games = new Map();                    // game_id → game object
    this.gameMeta = new Map();                 // game_id → meta (slot_sig, turn_sig, etc)
    this.gameSpectators = new Map();           // game_id → Set<username>

    // User state
    this.wsByUser = new Map();                 // username → ws (connection)
    this.userByWs = new Map();                 // ws → username
    this.userToGame = new Map();               // username → game_id (currently playing)
    this.userToSpectate = new Map();           // username → game_id (currently spectating)

    // Temporary state
    this.readyPlayers = new Map();             // username → is_ready flag
    this.pendingInviteTo = new Map();          // username → {from, to, accepted}
  }

  // ========================
  // GAMES
  // ========================

  getGame(game_id) {
    return this.games.get(game_id);
  }

  setGame(game_id, game) {
    this.games.set(game_id, game);
  }

  hasGame(game_id) {
    return this.games.has(game_id);
  }

  deleteGame(game_id) {
    this.games.delete(game_id);
    this.gameMeta.delete(game_id);
    this.gameSpectators.delete(game_id);
  }

  getAllGames() {
    return Array.from(this.games.values());
  }

  getGamesCount() {
    return this.games.size;
  }

  // ========================
  // GAME META
  // ========================

  getGameMeta(game_id) {
    return this.gameMeta.get(game_id);
  }

  setGameMeta(game_id, meta) {
    this.gameMeta.set(game_id, meta);
  }

  // ========================
  // GAME SPECTATORS
  // ========================

  addGameSpectator(game_id, username) {
    if (!this.gameSpectators.has(game_id)) {
      this.gameSpectators.set(game_id, new Set());
    }
    this.gameSpectators.get(game_id).add(username);
  }

  removeGameSpectator(game_id, username) {
    const spectators = this.gameSpectators.get(game_id);
    if (spectators) {
      spectators.delete(username);
    }
  }

  getGameSpectators(game_id) {
    const spectators = this.gameSpectators.get(game_id);
    return spectators ? Array.from(spectators) : [];
  }

  clearGameSpectators(game_id) {
    this.gameSpectators.delete(game_id);
  }

  // ========================
  // WEBSOCKETS
  // ========================

  registerUser(username, ws) {
    this.wsByUser.set(username, ws);
    this.userByWs.set(ws, username);
  }

  unregisterUser(username, ws) {
    this.wsByUser.delete(username);
    this.userByWs.delete(ws);
  }

  getWS(username) {
    return this.wsByUser.get(username);
  }

  getUsername(ws) {
    return this.userByWs.get(ws);
  }

  getAllConnectedUsers() {
    return Array.from(this.wsByUser.keys());
  }

  getAllConnections() {
    return Array.from(this.wsByUser.entries());
  }

  getConnectionsCount() {
    return this.wsByUser.size;
  }

  // ========================
  // USER GAMES
  // ========================

  setUserGame(username, game_id) {
    this.userToGame.set(username, game_id);
  }

  getUserGame(username) {
    return this.userToGame.get(username);
  }

  removeUserGame(username) {
    this.userToGame.delete(username);
  }

  hasUserGame(username) {
    return this.userToGame.has(username);
  }

  getGameUsers(game_id) {
    const users = [];
    for (const [username, gid] of this.userToGame.entries()) {
      if (gid === game_id) users.push(username);
    }
    return users;
  }

  // ========================
  // USER SPECTATIONS
  // ========================

  setUserSpectate(username, game_id) {
    this.userToSpectate.set(username, game_id);
  }

  getUserSpectate(username) {
    return this.userToSpectate.get(username);
  }

  removeUserSpectate(username) {
    this.userToSpectate.delete(username);
  }

  hasUserSpectate(username) {
    return this.userToSpectate.has(username);
  }

  // ========================
  // READY PLAYERS
  // ========================

  setPlayerReady(username, ready = true) {
    this.readyPlayers.set(username, ready);
  }

  isPlayerReady(username) {
    return this.readyPlayers.get(username) ?? false;
  }

  clearPlayerReady(username) {
    this.readyPlayers.delete(username);
  }

  getAllReadyPlayers() {
    return Array.from(this.readyPlayers.keys());
  }

  // ========================
  // PENDING INVITES
  // ========================

  setPendingInvite(username, invite) {
    this.pendingInviteTo.set(username, invite);
  }

  getPendingInvite(username) {
    return this.pendingInviteTo.get(username);
  }

  removePendingInvite(username) {
    this.pendingInviteTo.delete(username);
  }

  // ========================
  // UTILITIES
  // ========================

  /**
   * Obtenir un snappoint complet de l'état pour debug/monitoring
   */
  getSnapshot() {
    return {
      games_count: this.games.size,
      users_count: this.wsByUser.size,
      users_in_game: this.userToGame.size,
      users_spectating: this.userToSpectate.size,
      ready_players: this.readyPlayers.size,
      pending_invites: this.pendingInviteTo.size,
    };
  }

  /**
   * Nettoyer un utilisateur complètement (déconnexion)
   */
  cleanupUser(username) {
    this.wsByUser.delete(username);
    const ws = Array.from(this.userByWs.entries()).find(([_, u]) => u === username)?.[0];
    if (ws) this.userByWs.delete(ws);
    this.userToGame.delete(username);
    this.userToSpectate.delete(username);
    this.readyPlayers.delete(username);
    this.pendingInviteTo.delete(username);
  }
}

/**
 * Créer une instance de StateManager
 * @returns {StateManager}
 */
export function createStateManager() {
  return new StateManager();
}
