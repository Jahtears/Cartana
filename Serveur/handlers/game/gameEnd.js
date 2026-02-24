// handlers/gameEnd.js v1.1

import { getExistingGameOrRes, getGameIdFromDataOrMapping } from "../../net/guards.js";
import { resError } from "../../net/transport.js";
import { ensureGameMeta } from "../../game/meta.js";
import { GAME_END_REASONS } from "../../game/constants/gameEnd.js";
import { POPUP_MESSAGE } from "../../shared/popupMessages.js";

const CLEANUP_TTL_MS = 2 * 60 * 1000;
const ACK_INTENT_REMATCH = "rematch";

export const POST_GAME_STATES = Object.freeze({
  ENDED: "ended",
  REMATCH_PENDING: "rematch_pending",
  RESOLVED: "resolved",
  EXPIRED: "expired",
});

function isPostGameState(value) {
  return Object.values(POST_GAME_STATES).includes(value);
}

export function ensureGameEndMeta(gameMeta, game_id, { initialSent = true } = {}) {
  const meta = ensureGameMeta(gameMeta, game_id, { initialSent });
  if (!(meta.acks instanceof Set)) meta.acks = new Set();
  if (typeof meta.endedAt !== "number" || !Number.isFinite(meta.endedAt)) meta.endedAt = 0;
  if (typeof meta.lastAckAt !== "number" || !Number.isFinite(meta.lastAckAt)) meta.lastAckAt = 0;
  if (!isPostGameState(meta.post_game_state)) {
    meta.post_game_state = meta.result ? POST_GAME_STATES.ENDED : "";
  }
  return meta;
}

function clearCleanupTimer(meta) {
  if (meta?.cleanupTimer) {
    clearTimeout(meta.cleanupTimer);
    meta.cleanupTimer = null;
  }
}

export function cleanupIfOrphaned(ctx, game_id, { reason = "", allowPending = false } = {}) {
  const {
    state,
    deleteGameState,
    refreshLobby,
  } = ctx;
  const { games, gameMeta, readyPlayers, gameSpectators, userToGame } = state;

  if (!games.has(game_id)) {
    if (gameMeta.has(game_id)) {
      const meta = gameMeta.get(game_id);
      clearCleanupTimer(meta);
      gameMeta.delete(game_id);
    }
    return false;
  }

  const game = games.get(game_id);
  const stillPlayersAttached = game.players.some((p) => userToGame.get(p) === game_id);
  const spectatorsCount = gameSpectators.get(game_id)?.size ?? 0;

  if (stillPlayersAttached || spectatorsCount > 0) return false;

  const meta = gameMeta.get(game_id);
  if (meta?.post_game_state === POST_GAME_STATES.REMATCH_PENDING && !allowPending) return false;

  if (reason === "ttl" && meta?.post_game_state === POST_GAME_STATES.REMATCH_PENDING) {
    meta.post_game_state = POST_GAME_STATES.EXPIRED;
  }
  clearCleanupTimer(meta);
  readyPlayers.delete(game_id);
  state.deleteGame(game_id);
  deleteGameState(game_id);
  refreshLobby();
  return true;
}

function scheduleCleanup(ctx, game_id, reason) {
  const { state } = ctx;
  const { gameMeta } = state;
  if (!gameMeta || !game_id) return;

  const meta = ensureGameEndMeta(gameMeta, game_id, { initialSent: true });
  if (meta.cleanupTimer) return;

  meta.cleanupTimer = setTimeout(() => {
    meta.cleanupTimer = null;
    const liveMeta = gameMeta.get(game_id);
    if (liveMeta?.post_game_state === POST_GAME_STATES.REMATCH_PENDING) {
      liveMeta.post_game_state = POST_GAME_STATES.EXPIRED;
    }
    cleanupIfOrphaned(ctx, game_id, { reason: reason || "ttl", allowPending: true });
  }, CLEANUP_TTL_MS);

  if (typeof meta.cleanupTimer?.unref === "function") meta.cleanupTimer.unref();
}

function endGame(ctx, game_id, result, { exclude = [] } = {}) {
  if (!game_id) return { payload: null, created: false };

  const { state, emitGameEndOnce, emitSnapshotsToAudience } = ctx;
  const { gameMeta } = state;
  const meta = ensureGameEndMeta(gameMeta, game_id, { initialSent: true });

  const res = emitGameEndOnce(game_id, result, { exclude });

  if (res.created) {
    meta.acks = new Set();
    meta.endedAt = Date.now();
    meta.post_game_state = POST_GAME_STATES.ENDED;
  }

  emitSnapshotsToAudience(game_id, { reason: "game_end" });

  if (res.created) scheduleCleanup(ctx, game_id, "game_end");
  return res;
}

function resolveAckGameId(ctx, ws, req, data, actor) {
  return (
    getGameIdFromDataOrMapping(ctx, ws, req, data, actor, {
      required: false,
      preferMapping: true,
      allowedKeys: ["game_id"],
    }) ?? ""
  );
}

function getAckMembership(state, game_id, actor) {
  const { gameSpectators, userToGame, userToSpectate } = state;
  const wasPlayer = !!(game_id && userToGame.get(actor) === game_id);
  const wasSpec = !!(
    game_id &&
    (userToSpectate.get(actor) === game_id || (gameSpectators.get(game_id)?.has(actor) ?? false))
  );
  return { wasPlayer, wasSpec };
}

function sendAckResponse(refreshLobby, sendRes, ws, req, payload) {
  refreshLobby();
  sendRes(ws, req, true, payload);
  return true;
}

function handleAlreadyGoneAck(games, gameMeta, game_id) {
  if (game_id && games.has(game_id)) return false;
  if (gameMeta.has(game_id)) {
    const meta = gameMeta.get(game_id);
    clearCleanupTimer(meta);
    gameMeta.delete(game_id);
  }
  return true;
}

function maybeEndByAckAsAbandon(ctx, game_id, game, actor, wasPlayer, meta) {
  if (!wasPlayer || meta.result) return;
  const winner = game.players.find((p) => p !== actor) ?? null;
  endGame(
    ctx,
    game_id,
    { winner, reason: GAME_END_REASONS.ABANDON, by: actor, at: Date.now() },
    { exclude: [actor] }
  );
}

function recordAckAndSchedule(ctx, meta, game_id, actor) {
  meta.acks.add(actor);
  meta.lastAckAt = Date.now();
  if (meta.result && !meta.endedAt) meta.endedAt = Date.now();
  if (meta.result && !meta.cleanupTimer) scheduleCleanup(ctx, game_id, "ack");
}

export function handleLeaveGame(ctx, ws, req, data, actor) {
  const {
    setUserActivity,
    Activity,
    sendRes,
    refreshLobby,
  } = ctx;
  const game_id = getGameIdFromDataOrMapping(ctx, ws, req, data, actor, {
    required: true,
    preferMapping: true,
    allowedKeys: ["game_id"],
  });

  if (!game_id) return true;

  const game = getExistingGameOrRes(ctx, ws, req, game_id);
  if (!game) return true;

  if (!game.players.includes(actor)) {
    return resError(sendRes, ws, req, POPUP_MESSAGE.TECH_FORBIDDEN)
  }

  // abandonneur sort (l’adversaire / specs restent attachés jusqu’à ack)
  setUserActivity(actor, Activity.LOBBY, null);

  // ✅ game_end idempotent/once (uniquement à la création du result)
  const winner = game.players.find((p) => p !== actor) ?? null;

  endGame(
    ctx,
    game_id,
    { winner, reason: GAME_END_REASONS.ABANDON, by: actor, at: Date.now() },
    { exclude: [actor] }
  );

  refreshLobby();

  sendRes(ws, req, true, { left: true, game_id });
  return true;
}

export function handleAckGameEnd(ctx, ws, req, data, actor) {
  const {
    state,
    setUserActivity,
    Activity,
    sendRes,
    refreshLobby,
  } = ctx;
  const { games, gameMeta } = state;
  const game_id = resolveAckGameId(ctx, ws, req, data, actor);
  const ackIntent = String(data?.intent ?? "").trim().toLowerCase();

  // idempotent: sans game_id -> OK
  if (!game_id) {
    return sendAckResponse(refreshLobby, sendRes, ws, req, {
      ack: true,
      game_id: "",
      alreadyGone: true,
    });
  }

  // déterminer l’appartenance AVANT detach
  const { wasPlayer, wasSpec } = getAckMembership(state, game_id, actor);

  // ✅ detach idempotent (joueur + spectateur)
  setUserActivity(actor, Activity.LOBBY, null);

  // ✅ ACK idempotent : si game inexistante => OK
  if (handleAlreadyGoneAck(games, gameMeta, game_id)) {
    return sendAckResponse(refreshLobby, sendRes, ws, req, {
      ack: true,
      game_id,
      alreadyGone: true,
    });
  }

  const game = games.get(game_id);

  // si pas concerné: OK mais pas de cleanup
  if (!wasPlayer && !wasSpec) {
    return sendAckResponse(refreshLobby, sendRes, ws, req, {
      ack: true,
      game_id,
      ignored: true,
    });
  }

  const meta = ensureGameEndMeta(gameMeta, game_id, { initialSent: true });

  // ✅ si un joueur ACK alors que la partie n'est pas finie => traiter comme abandon
  maybeEndByAckAsAbandon(ctx, game_id, game, actor, wasPlayer, meta);
  if (ackIntent === ACK_INTENT_REMATCH && wasPlayer && meta.result) {
    meta.post_game_state = POST_GAME_STATES.REMATCH_PENDING;
  }
  recordAckAndSchedule(ctx, meta, game_id, actor);

  cleanupIfOrphaned(ctx, game_id, { reason: "ack" });

  return sendAckResponse(refreshLobby, sendRes, ws, req, { ack: true, game_id });
}
