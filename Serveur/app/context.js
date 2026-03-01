// server/context.js v3.1 - Utilise StateManager + Notifier pour émission

import { randomUUID } from "node:crypto";
import { createTransport } from "../net/transport.js";
import { createBroadcaster } from "../net/broadcast/broadcaster.js";
import { createFlush } from "../net/broadcast/flush.js";
import { createRoles } from "../domain/roles/roles.js";
import { createLobbyLists } from "../domain/lobby/lists.js";
import { createGameNotifier } from "../domain/session/notifier.js";
import { emitSlotState, emitFullState } from "../domain/session/emitter.js";
import { createPresence } from "../domain/session/presence.js";
import { createGame } from "../game/factory/createGame.js";
import { getCardById } from "../game/state/cardStore.js";
import { mapSlotFromClientToServer, mapSlotForClient } from "../game/boundary/slotIdMapper.js";
import { getTableSlots } from "../game/helpers/tableHelper.js";
import { applyMove } from "../game/engine/applyMove.js";
import { validateMove, refillHandIfEmpty, hasWonByEmptyDeckSlot, hasLoseByEmptyPileSlot } from "../game/rules/validateMove.js";
import { orchestrateMove } from "../game/usecases/move/orchestrateMove.js";
import { orchestrateTurnTimeout } from "../game/usecases/turn/orchestrateTurnTimeout.js";
import {
  initTurnForGame,
  endTurnAfterBenchPlay,
  resetTurnTimeoutStreak,
} from "../game/helpers/turnFlowHelpers.js";
import { INGAME_MESSAGE } from "../game/constants/ingameMessages.js";
import { buildCardPayload } from "../game/payload/cardPayload.js";
import { buildTurnPayload } from "../game/payload/turnPayload.js";
import { buildStateSnapshotPayload } from "../game/payload/snapshotPayload.js";
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
    userToEndGame: state.userToEndGame,
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
    state,
    sendEvtLobby,
    getUserStatus,
  });

  // ========================
  // NOTIFIER
  // ========================
  const { emitStartGameToUser, emitSnapshotsToAudience, emitGameEndOnce } = createGameNotifier({
    state,
    sendEvtSocket,
    sendEvtUser,
  });

  // ========================
  // HELPERS
  // ========================

  function generateGameID() {
    return `game_${randomUUID()}`;
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
      touch(slot_id) {
        if (!slot_id) return;
        fl.touch(slot_id);
      },

      syncTable(tableSlots) {
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
    const game = state.games.get(gameId);
    if (!game?.turn) return false;

    const meta = state.gameMeta.get(gameId);
    if (game.turn.paused || meta?.result) return false;

    const timeoutResult = orchestrateTurnTimeout({ game, now });
    if (!timeoutResult?.expired) return false;

    const prev = String(timeoutResult.prev ?? "").trim();
    const next = String(timeoutResult.next ?? "").trim();
    const endGamePatch = timeoutResult.endGamePatch;

    if (prev) {
      emitGameMessage(
        sendEvtUser,
        prev,
        { message_code: INGAME_MESSAGE.TURN_TIMEOUT }
      );
    }
    if (next && !endGamePatch) {
      emitGameMessage(
        sendEvtUser,
        next,
        { message_code: INGAME_MESSAGE.TURN_START }
      );
    }

    if (endGamePatch) {
      emitGameEndOnce(gameId, endGamePatch);
      saveGameState(gameId, game);
      emitSnapshotsToAudience(gameId, { reason: "game_end" });
      return timeoutResult;
    }

    saveGameState(gameId, game);
    emitSnapshotsToAudience(gameId, { reason: "turn_timeout" });
    return timeoutResult;
  }

  // ========================
  // PRESENCE (disconnect/reconnect)
  // ========================
  const { handleReconnect, onSocketClose } = createPresence({
    state,
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

    // Facades use-cases
    usecases: {
      move: {
        orchestrateMove,
        validateMove,
        applyMove,
        getCardById,
        refillHandIfEmpty,
        hasWonByEmptyDeckSlot,
        hasLoseByEmptyPileSlot,
      },
      turn: {
        initTurnForGame,
        endTurnAfterBenchPlay,
        processTurnTimeout,
        resetTurnTimeoutStreak,
        getTableSlots,
        withGameUpdate,
      },
      session: {
        emitStartGameToUser,
        emitSnapshotsToAudience,
        emitGameEndOnce,
        emitFullState,
        emitSlotState,
      },
    },

    boundary: {
      slot: {
        mapSlotFromClientToServer,
        mapSlotForClient,
      },
    },

    factory: {
      game: {
        createGame,
      },
    },

    payload: {
      buildCardPayload,
      buildTurnPayload,
      buildStateSnapshotPayload,
    },

    // Keep selected direct helpers used by generic guards/handlers
    emitStartGameToUser,
    emitSnapshotsToAudience,
    emitGameEndOnce,
    emitFullState,
    emitSlotState,
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
