// handlers/gameEnd.js v1.1

import { getExistingGameOrRes, getGameIdFromDataOrMapping } from "../../net/guards.js";
import { resForbidden } from "../../net/transport.js";
import { ensureGameMeta } from "../../domain/game/meta.js";

const CLEANUP_TTL_MS = 2 * 60 * 1000;

function ensureGameEndMeta(gameMeta, game_id, { initialSent = true } = {}) {
  const meta = ensureGameMeta(gameMeta, game_id, { initialSent });
  if (!(meta.acks instanceof Set)) meta.acks = new Set();
  if (typeof meta.endedAt !== "number" || !Number.isFinite(meta.endedAt)) meta.endedAt = 0;
  if (typeof meta.lastAckAt !== "number" || !Number.isFinite(meta.lastAckAt)) meta.lastAckAt = 0;
  return meta;
}

function clearCleanupTimer(meta) {
  if (meta?.cleanupTimer) {
    clearTimeout(meta.cleanupTimer);
    meta.cleanupTimer = null;
  }
}

function cleanupIfOrphaned(ctx, game_id, { reason = "" } = {}) {
  const {
    state,
    deleteGameState,
    refreshLobby,
  } = ctx;
  const { games, gameMeta, readyPlayers, gameSpectators, userToGame } = state;

  if (!game_id || !games?.has(game_id)) {
    if (gameMeta?.has(game_id)) {
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
  clearCleanupTimer(meta);
  readyPlayers.delete(game_id);
  gameMeta.delete(game_id);
  games.delete(game_id);
  if (typeof deleteGameState === "function") deleteGameState(game_id);
  if (typeof refreshLobby === "function") refreshLobby();
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
    cleanupIfOrphaned(ctx, game_id, { reason: reason || "ttl" });
  }, CLEANUP_TTL_MS);

  if (typeof meta.cleanupTimer?.unref === "function") meta.cleanupTimer.unref();
}

function endGame(ctx, game_id, result, { exclude = [] } = {}) {
  if (!game_id) return { payload: null, created: false };

  const { state, emitGameEndOnce, emitSnapshotsToAudience } = ctx;
  const { gameMeta } = state;
  const meta = ensureGameEndMeta(gameMeta, game_id, { initialSent: true });

  const res = typeof emitGameEndOnce === "function"
    ? emitGameEndOnce(game_id, result, { exclude })
    : { payload: null, created: false };

  if (res.created) {
    meta.acks = new Set();
    meta.endedAt = Date.now();
  }

  if (typeof emitSnapshotsToAudience === "function") {
    emitSnapshotsToAudience(game_id, { reason: "game_end" });
  }

  if (res.created) scheduleCleanup(ctx, game_id, "game_end");
  return res;
}

export function handleLeaveGame(ctx, ws, req, data, actor) {
  const {
    setUserActivity,
    Activity,
    sendResponse,
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

  if (!game || !game.players.includes(actor)) {
    return resForbidden(sendResponse, ws, req, "Tu n'es pas dans cette partie")
  }

  // abandonneur sort (l’adversaire / specs restent attachés jusqu’à ack)
  setUserActivity(actor, Activity.LOBBY, null);

  // ✅ game_end idempotent/once (uniquement à la création du result)
  const winner = game.players.find((p) => p !== actor) ?? null;

  endGame(ctx, game_id, { winner, reason: "abandon", by: actor, at: Date.now() }, { exclude: [actor] });

  if (typeof refreshLobby === "function") refreshLobby();

  sendResponse(ws, req, true, { left: true, game_id });
  return true;
}

export function handleAckGameEnd(ctx, ws, req, data, actor) {
  const {
    state,
    setUserActivity,
    Activity,
    sendResponse,
    refreshLobby,
  } = ctx;
  const { games, gameMeta, gameSpectators, userToGame, userToSpectate } = state;

  const game_id =
    getGameIdFromDataOrMapping(ctx, ws, req, data, actor, {
      required: false,
      preferMapping: true,
      allowedKeys: ["game_id"],
  }) ?? "";

  // idempotent: sans game_id -> OK
  if (!game_id) {
    if (typeof refreshLobby === "function") refreshLobby();
    sendResponse(ws, req, true, { ack: true, game_id: "", alreadyGone: true });
    return true;
  }


  // déterminer l’appartenance AVANT detach
  const wasPlayer = !!(game_id && userToGame.get(actor) === game_id);
  const wasSpec = !!(
    game_id &&
    (userToSpectate.get(actor) === game_id || (gameSpectators.get(game_id)?.has(actor) ?? false))
  );

  // ✅ detach idempotent (joueur + spectateur)
  setUserActivity(actor, Activity.LOBBY, null);

  // ✅ ACK idempotent : si game inexistante => OK
  if (!game_id || !games.has(game_id)) {
    if (gameMeta?.has(game_id)) {
      const meta = gameMeta.get(game_id);
      clearCleanupTimer(meta);
      gameMeta.delete(game_id);
    }
    if (typeof refreshLobby === "function") refreshLobby();
    sendResponse(ws, req, true, { ack: true, game_id, alreadyGone: true });
    return true;
  }

  const game = games.get(game_id);

  // si pas concerné: OK mais pas de cleanup
  if (!wasPlayer && !wasSpec) {
    if (typeof refreshLobby === "function") refreshLobby();
    sendResponse(ws, req, true, { ack: true, game_id, ignored: true });
    return true;
  }

  const meta = ensureGameEndMeta(gameMeta, game_id, { initialSent: true });

  // ✅ si un joueur ACK alors que la partie n'est pas finie => traiter comme abandon
  if (wasPlayer && !meta.result) {
    const winner = game.players.find((p) => p !== actor) ?? null;
    endGame(ctx, game_id, { winner, reason: "abandon", by: actor, at: Date.now() }, { exclude: [actor] });
  }

  meta.acks.add(actor);
  meta.lastAckAt = Date.now();
  if (meta.result && !meta.endedAt) meta.endedAt = Date.now();

  if (meta.result && !meta.cleanupTimer) scheduleCleanup(ctx, game_id, "ack");

  cleanupIfOrphaned(ctx, game_id, { reason: "ack" });

  if (typeof refreshLobby === "function") refreshLobby();
  sendResponse(ws, req, true, { ack: true, game_id });
  return true;
}
