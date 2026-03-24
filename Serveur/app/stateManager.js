// app/stateManager.js - Gestionnaire d'état centralisé

export class StateManager {
  constructor() {
    // Game state
    this.games = new Map(); // game_id → game object
    this.gameMeta = new Map(); // game_id → meta (slot_sig, turn_sig, etc)
    this.gameSpectators = new Map(); // game_id → Set<username>

    // User state
    this.wsByUser = new Map(); // username → ws
    this.userByWs = new Map(); // ws → username
    this.userToGame = new Map(); // username → game_id (en train de jouer)
    this.userToSpectate = new Map(); // username → game_id (en train de spectater)

    // Temporary state
    this.readyPlayers = new Map(); // game_id → Set<username> (barrière d'entrée des joueurs)
    this.pendingInviteTo = new Map(); // username → {from, to, accepted}
    this.inviteFrom = new Map(); // username(from) → username(to)
    this.userToEndGame = new Map(); // username -> game_id (post game_end, avant sortie effective)
  }

  // ========================
  // GAMES — opérations composées uniquement
  // ========================

  /** Supprime une partie et toutes ses données associées */
  deleteGame(game_id) {
    for (const [username, gid] of this.userToEndGame.entries()) {
      if (gid === game_id) {
        this.userToEndGame.delete(username);
      }
    }
    this.games.delete(game_id);
    this.gameMeta.delete(game_id);
    this.gameSpectators.delete(game_id);
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

  getWS(username) {
    return this.wsByUser.get(username);
  }
  getUsername(ws) {
    return this.userByWs.get(ws);
  }
}

export function createStateManager() {
  return new StateManager();
}
