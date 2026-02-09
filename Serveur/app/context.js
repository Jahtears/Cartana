// server/context.js v3.1 - Utilise StateManager + Notifier pour émission

import { createTransport } from "../net/transport.js";
import { createRoles } from "../domain/roles/roles.js";
import { createLobbyLists } from "../domain/lobby/lists.js";
import { createGameNotifier, emitSlotState, emitFullState } from "../domain/session/index.js";
import { createPresence } from "../domain/session/presence.js";
import { createStateManager } from "./stateManager.js";

export function createServerContext(deps) {
  const {
    createGame,
    getTableSlots,
    findCardById,
    mapSlotFromClientToServer,
    mapSlotForClient,
    validateMove,
    applyMove,
    initTurnForGame,
    isBenchSlot,
    endTurnAfterBenchPlay,
    refillHandIfEmpty,
    hasWonByEmptyDeckSlot,
    saveGameState,
    loadGameState,
    deleteGameState,
    verifyOrCreateUser,
  } = deps;

  // ========================
  // STATE MANAGER (CENTRALISÉ)
  // ========================
  const state = createStateManager();

  // ========================
  // TRANSPORT
  // ========================
  const { sendResponse, sendEvent, sendEventToUser, sendLobbyEvent } = createTransport({ 
    wsByUser: state.wsByUser 
  });

  // ========================
  // ROLES
  // ========================
  const {
    Activity,
    getUserStatus,
    setUserActivity,
    attachSpectator,
    detachSpectator,
    clearInvitesForUser,
  } = createRoles({
    wsByUser: state.wsByUser,
    userToGame: state.userToGame,
    userToSpectate: state.userToSpectate,
    gameSpectators: state.gameSpectators,
    pendingInviteTo: state.pendingInviteTo,
    gameMeta: state.gameMeta,
    sendEventToUser,
  });

  // ========================
  // LOBBY LISTS
  // ========================
  const {
    gamesList,
    playersList,
    playersStatuses,
    broadcastPlayersList,
    broadcastGamesList,
    refreshLobby,
  } = createLobbyLists({
    games: state.games,
    gameMeta: state.gameMeta,
    gameSpectators: state.gameSpectators,
    wsByUser: state.wsByUser,
    sendLobbyEvent,
    getUserStatus,
  });

  // ========================
  // NOTIFIER
  // ========================
  const { emitStartGameToUser, emitSnapshotsToAudience, emitGameEndOnce } = createGameNotifier({
    games: state.games,
    gameMeta: state.gameMeta,
    gameSpectators: state.gameSpectators,
    wsByUser: state.wsByUser,
    sendEvent,
    sendEventToUser,
  });

  // ========================
  // HELPERS
  // ========================

  function generateGameID() {
    return "game_" + Math.random().toString(36).substr(2, 9);
  }

  function withGameUpdate(game_id, callback, trace) {
    const game = state.getGame(game_id);
    if (!game) return;

    // Créer un builder avec les méthodes attendues
    const fx = {
      game,
      touches: new Set(),
      messages: [],

      touch(slot_id) {
        this.touches.add(slot_id);
      },

      syncTable(tableSlots) {
        game.tableSlots = tableSlots;
      },

      turn() {
        // Passer au tour suivant
        if (game.turn && typeof game.turn.next === 'function') {
          game.turn.next();
        }
      },

      message(type, data, opts) {
        this.messages.push({ type, data, opts });
      },
    };

    // Exécuter le callback avec le builder
    callback(fx);

    // Broadcaster les mises à jour
    emitSnapshotsToAudience(game_id, game);
  }

  function notifyOpponent(game_id, game, evtType, data) {
    if (!game) return;
    const actor = String(data?.username ?? "");
    for (const player of game.players ?? []) {
      const username = typeof player === "string" ? player : String(player?.username ?? "");
      if (!username || username === actor) continue;
      sendEventToUser(username, evtType, data);
    }
  }

  // ========================
  // PRESENCE (disconnect/reconnect)
  // ========================
  const { handleReconnect, onSocketClose } = createPresence({
    games: state.games,
    gameMeta: state.gameMeta,
    userToGame: state.userToGame,
    userToSpectate: state.userToSpectate,
    userByWs: state.userByWs,
    wsByUser: state.wsByUser,
    detachSpectator,
    clearInvitesForUser,
    sendEventToUser,
    saveGameState,
    loadGameState,
    refreshLobby,
    notifyOpponent,
    emitStartGameToUser,
    emitSnapshotsToAudience,
  });

  // ========================
  // BASE CONTEXT (pour handlers)
  // ========================
  const baseCtx = {
    // State manager (accès complet à l'état)
    state,

    // Transport (helpers d'envoi)
    sendResponse,
    sendEvent,
    sendEventToUser,
    sendLobbyEvent,

    // Roles (gestion des statuts/activités)
    Activity,
    getUserStatus,
    setUserActivity,
    attachSpectator,
    detachSpectator,
    clearInvitesForUser,

    // Lobby (listes et broadcasts)
    playersStatuses,
    gamesList,
    playersList,
    broadcastPlayersList,
    broadcastGamesList,
    refreshLobby,

    // Notifier (événements de jeu)
    emitStartGameToUser,
    emitSnapshotsToAudience,
    emitGameEndOnce,

    // Game engine (logique métier)
    createGame,
    emitSlotState,
    emitFullState,
    getTableSlots,
    findCardById,
    mapSlotFromClientToServer,
    mapSlotForClient,
    validateMove,
    applyMove,
    initTurnForGame,
    isBenchSlot,
    endTurnAfterBenchPlay,
    refillHandIfEmpty,
    hasWonByEmptyDeckSlot,
    withGameUpdate,

    // Persist (sauvegarde)
    saveGameState,
    loadGameState,
    deleteGameState,

    // Helpers
    generateGameID,
    notifyOpponent,
    handleReconnect,
  };

  // ========================
  // LOGIN CONTEXT
  // ========================
  const loginCtx = {
    ...baseCtx,
    verifyOrCreateUser,
  };

  return {
    baseCtx,
    loginCtx,
    onSocketClose,
    
  };
}
