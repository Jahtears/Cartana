// server/context.js v3.1 - Utilise StateManager + Notifier pour émission

import { createTransport } from "../net/transport.js";
import { createRoles } from "../domain/roles/roles.js";
import { createLobbyLists } from "../domain/lobby/lists.js";
import { createGameNotifier, emitSlotState, emitFullState } from "../domain/session/index.js";
import { createPresence } from "../domain/session/presence.js";
import { createStateManager } from "./stateManager.js";
import { GAME_MESSAGE } from "../shared/constants.js";
import { toUiMessage } from "../shared/uiMessage.js";

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
    timeoutTurnIfExpired,
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
  const {
    sendRes,
    sendEvtSocket,
    sendEvtUser,
    sendEvtLobby,
  } = createTransport({
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

    // Emettre les messages applicatifs accumulés (show_game_message, etc.)
    if (fx.messages.length) {
      const specs = state.gameSpectators.get(game_id);
      const audience = [
        ...(Array.isArray(game.players) ? game.players : []),
        ...(specs ? Array.from(specs) : []),
      ];

      for (const msg of fx.messages) {
        const type = String(msg?.type ?? "").trim();
        if (!type) continue;
        const data = msg?.data && typeof msg.data === "object" ? msg.data : {};
        const to = msg?.opts?.to ?? null;
        const recipients = Array.isArray(to) ? to : (to ? [to] : audience);
        const uniqueRecipients = new Set(recipients.filter(Boolean).map((u) => String(u)));

        for (const username of uniqueRecipients) {
          sendEvtUser(username, type, data);
        }
      }
    }

    // Broadcaster les mises à jour d'état (snapshot)
    emitSnapshotsToAudience(game_id, { reason: "with_game_update" });
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

  function expireTurnIfNeeded(game_id, now = Date.now()) {
    if (typeof timeoutTurnIfExpired !== "function") return false;

    const game = state.getGame(game_id);
    if (!game?.turn) return false;

    const meta = state.gameMeta.get(game_id);
    if (meta?.pause?.active || meta?.result) return false;

    const expired = timeoutTurnIfExpired(game, now);
    if (!expired) return false;

    const prev = String(expired.prev ?? "").trim();
    const next = String(expired.next ?? "").trim();

    if (prev) {
      sendEvtUser(
        prev,
        "show_game_message",
        toUiMessage({ text: "Temps ecoule.", code: GAME_MESSAGE.WARN }, { code: GAME_MESSAGE.WARN })
      );
    }
    if (next) {
      sendEvtUser(
        next,
        "show_game_message",
        toUiMessage({ text: "A vous de jouer.", code: GAME_MESSAGE.TURN_START }, { code: GAME_MESSAGE.INFO })
      );
    }

    saveGameState(game_id, game);
    emitSnapshotsToAudience(game_id, { reason: "turn_timeout" });
    return expired;
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
    expireTurnIfNeeded,

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
