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
import { SLOT_TYPES, SlotId } from "../game/constants/slots.js";
import { getCardById } from "../game/state/cardStore.js";
import { getTableSlots } from "../game/state/slotStore.js";
import { mapSlotFromClientToServer, mapSlotForClient } from "../game/boundary/slotIdMapper.js";
import { applyMove } from "../game/engine/applyMove.js";
import { validateMove, refillHandIfEmpty, hasWonByEmptyDeckSlot, hasLoseByEmptyPileSlot } from "../game/rules/validateMove.js";
import { orchestrateMove } from "../game/usecases/move/orchestrateMove.js";
import {
  initTurnForGame,
  endTurnAfterBenchPlay,
  resetTurnTimeoutStreak,
  tryExpireTurn,
} from "../game/helpers/turnFlowHelpers.js";
import { buildCardPayload } from "../game/payload/cardPayload.js";
import { buildTurnPayload } from "../game/payload/turnPayload.js";
import { buildStateSnapshotPayload } from "../game/payload/snapshotPayload.js";
import { saveGameState, loadGameState, deleteGameState } from "../domain/session/Saves.js";
import { verifyOrCreateUser } from "../handlers/auth/usersStore.js";
import { createStateManager } from "./stateManager.js";

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

  function processTurnTimeout(gameId, now = Date.now()) {
    const game = state.games.get(gameId);
    if (!game?.turn) return false;

    const meta = state.gameMeta.get(gameId);
    if (game.turn.paused || meta?.result) return false;

    const timeoutResult = tryExpireTurn(game, now);
    if (!timeoutResult?.expired) return false;

    const prev = String(timeoutResult.prev ?? "").trim();
    const next = String(timeoutResult.next ?? "").trim();
    const endGamePatch = timeoutResult.endGamePatch;
    const pileSlotId = SlotId.create(0, SLOT_TYPES.PILE, 1);

    withGameUpdate(gameId, (fx) => {
      const recycledSlots = timeoutResult.recycled?.recycledSlots;
      if (timeoutResult.tableSyncNeeded || (Array.isArray(recycledSlots) && recycledSlots.length > 0)) {
        fx.syncTable(getTableSlots(game));
      }

      const autoPlayedAces = Array.isArray(timeoutResult.autoPlayedAces)
        ? timeoutResult.autoPlayedAces
        : [];
      if (autoPlayedAces.length > 0) {
        for (const move of autoPlayedAces) {
          if (move?.from) fx.touch(move.from);
          if (move?.to) fx.touch(move.to);
        }
      } else {
        if (timeoutResult.aceFrom) fx.touch(timeoutResult.aceFrom);
        if (timeoutResult.aceTo) fx.touch(timeoutResult.aceTo);
      }
      for (const refill of timeoutResult.given ?? []) {
        if (refill?.slotId) fx.touch(refill.slotId);
      }
      fx.touch(pileSlotId);
      fx.turn();

      if (prev) {
        fx.message("show_game_message", { message_code: "RULE_TURN_TIMEOUT" }, { to: prev });
      }
      if (next && !endGamePatch) {
        fx.message("show_game_message", { message_code: "RULE_TURN_START" }, { to: next });
      }
    });

    saveGameState(gameId, game);
    if (endGamePatch) {
      emitGameEndOnce(gameId, endGamePatch);
      emitSnapshotsToAudience(gameId, { reason: "game_end" });
    }
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
