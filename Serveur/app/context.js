// server/context.js v3.1 - Utilise StateManager + Notifier pour émission

import { createTransport } from "../net/transport.js";
import { createBroadcaster, createFlush } from "../net/broadcast.js";
import { createRoles } from "../domain/roles/roles.js";
import { createLobbyLists } from "../domain/lobby/lists.js";
import { createGameNotifier, emitSlotState, emitFullState } from "../domain/session/index.js";
import { createPresence } from "../domain/session/presence.js";
import { createGame } from "../game/builders/gameBuilder.js";
import { getCardById } from "../game/helpers/cardHelpers.js";
import { mapSlotFromClientToServer, mapSlotForClient } from "../game/helpers/slotHelpers.js";
import { getTableSlots } from "../game/helpers/tableHelper.js";
import { applyMove } from "../game/MoveApplier.js";
import {
  validateMove,
  isBenchSlot,
  refillHandIfEmpty,
  hasWonByEmptyDeckSlot,
  haseLoseByEmptyPileSlot,
} from "../game/Regles.js";
import {
  TURN_FLOW_MESSAGES,
  initTurnForGame,
  endTurnAfterBenchPlay,
  tryExpireTurn,
} from "../game/helpers/turnFlowHelpers.js";
import { saveGameState, loadGameState, deleteGameState } from "../domain/session/Saves.js";
import { verifyOrCreateUser } from "../handlers/auth/usersStore.js";
import { createStateManager } from "./stateManager.js";
import { emitGameMessage } from "../shared/uiMessage.js";

export function createServerContext({ onTransportSend } = {}) {

  // ========================
  // STATE MANAGER (CENTRALISÉ)
  // ========================
  const state = createStateManager();

  // ========================
  // TRANSPORT
  // ========================
  const {
    sendRes,
    sendEvtSocket,
    sendEvtUser,
    sendEvtLobby,
  } = createTransport({
    wsByUser: state.wsByUser,
    onSend: onTransportSend,
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
    inviteFrom: state.inviteFrom,
    gameMeta: state.gameMeta,
    sendEvtUser,
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
    sendEvtLobby,
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
    sendEvtSocket,
    sendEvtUser,
  });

  // ========================
  // HELPERS
  // ========================

  function generateGameID() {
    return "game_" + Math.random().toString(36).substr(2, 9);
  }

  function withGameUpdate(game_id, callback, trace) {
    const game = state.games.get(game_id);
    if (!game) return;

    const specs = state.gameSpectators.get(game_id);
    const bc = createBroadcaster({
      game_id,
      game,
      specs,
      wsByUser: state.wsByUser,
      sendEvtSocket,
      sendEvtUser,
      emitSlotState,
      gameMeta: state.gameMeta,
    });
    const fl = createFlush(bc, trace);

    // Builder incrémental: table_sync -> slot_state -> turn_update -> messages.
    const fx = {
      game,
      touches: new Set(),

      touch(slot_id) {
        if (!slot_id) return;
        this.touches.add(slot_id);
        fl.touch(slot_id);
      },

      syncTable(tableSlots) {
        game.tableSlots = tableSlots;
        fl.syncTable(tableSlots);
      },

      turn() {
        fl.turn();
      },

      message(type, data, opts) {
        fl.message(type, data, opts);
      },
    };

    // Exécuter les mutations métier, puis flush incrémental.
    callback(fx);
    fl.flush();
  }

  function notifyOpponent(game_id, game, evtType, data) {
    if (!game) return;
    const actor = String(data?.username ?? "");
    for (const player of game.players ?? []) {
      const username = typeof player === "string" ? player : String(player?.username ?? "");
      if (!username || username === actor) continue;
      sendEvtUser(username, evtType, data);
    }
  }

  function processTurnTimeout(gameId, now = Date.now()) {
    if (typeof tryExpireTurn !== "function") return false;

    const game = state.games.get(gameId);
    if (!game?.turn) return false;

    const meta = state.gameMeta.get(gameId);
    if (game.turn.paused || meta?.result) return false;

    const timeoutResult = tryExpireTurn(game, now);
    if (!timeoutResult) return false;

    const prev = String(timeoutResult.prev ?? "").trim();
    const next = String(timeoutResult.next ?? "").trim();

    if (prev) {
      emitGameMessage(
        sendEvtUser,
        prev,
        { message_code: TURN_FLOW_MESSAGES.TIMEOUT }
      );
    }
    if (next) {
      emitGameMessage(
        sendEvtUser,
        next,
        { message_code: TURN_FLOW_MESSAGES.TURN_START }
      );
    }

    saveGameState(gameId, game);
    emitSnapshotsToAudience(gameId, { reason: "turn_timeout" });
    return timeoutResult;
  }

  // ========================
  // PRESENCE (disconnect/reconnect)
  // ========================
  const { handleReconnect, onSocketClose } = createPresence({
    games: state.games,
    gameMeta: state.gameMeta,
    gameSpectators: state.gameSpectators,
    userToGame: state.userToGame,
    userToSpectate: state.userToSpectate,
    userByWs: state.userByWs,
    wsByUser: state.wsByUser,
    detachSpectator,
    clearInvitesForUser,
    sendEvtUser,
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
    sendRes,
    sendEvtSocket,
    sendEvtUser,
    sendEvtLobby,

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
    getCardById,
    mapSlotFromClientToServer,
    mapSlotForClient,
    validateMove,
    applyMove,
    initTurnForGame,
    isBenchSlot,
    endTurnAfterBenchPlay,
    refillHandIfEmpty,
    hasWonByEmptyDeckSlot,
    haseLoseByEmptyPileSlot,
    withGameUpdate,
    processTurnTimeout,

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
