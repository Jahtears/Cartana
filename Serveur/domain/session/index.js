import { ensureGameMeta, ensureGameResult } from "../../game/meta.js";
import { GAME_END_REASONS } from "../../game/constants/gameEnd.js";
import { mapSlotForClient, isOwnerForSlot } from "../../game/helpers/slotHelpers.js";
import { buildCardData } from "../../game/builders/gameBuilder.js";
import { getTableSlots } from "../../game/helpers/tableHelper.js";
import { getSlotContent, getSlotType, isTableSlot, slotIdToString } from "../../game/helpers/slotHelpers.js";
import { applySlotDragPolicy, getVisibleCardIdsForSlot, toSlotStack } from "../../game/helpers/slotViewHelpers.js";
import { getCardById } from "../../game/helpers/cardHelpers.js";
import { getSlotCount } from "../../game/helpers/slotHelpers.js";
import { buildTurnPayload } from "../../game/helpers/turnPayloadHelpers.js";

/* =========================
   HELPERS FOR SLOT STATE
========================= */


function buildSlotStateForUser(game, username, slot_id, view, { forceDisableDrag = false } = {}) {
  const disableDrag = view === "spectator" || !!forceDisableDrag;

  const clientSlot = slotIdToString(
    view === "spectator" ? slot_id : mapSlotForClient(slot_id, username, game)
  );

  const isOwner = view === "spectator"
    ? false
    : isOwnerForSlot(game, slot_id, username);

  const cards = [];

  const slotValue = getSlotContent(game, slot_id);
  const stack = toSlotStack(slotValue);
  const count = getSlotCount(game, slot_id);

  if (!stack.length) return { slot_id: clientSlot, cards, count };

  const slotType = getSlotType(slot_id);
  const ids = getVisibleCardIdsForSlot(slotType, stack);

  for (let i = 0; i < ids.length; i++) {
    const card = getCardById(game, ids[i]);
    if (!card) continue;

    const payload = buildCardData(card, clientSlot, isOwner, disableDrag);
    payload.draggable = applySlotDragPolicy(slotType, stack, ids[i], payload.draggable);

    cards.push(payload);
  }

  return { slot_id: clientSlot, cards, count };
}

function publicGameEndResult(result) {
  if (!result || typeof result !== "object") {
    return {
      winner: null,
      reason: GAME_END_REASONS.ABANDON,
      by: "",
      at: 0,
    };
  }

  const winner =
    typeof result.winner === "string" && result.winner.trim()
      ? result.winner
      : null;
  const rawReason = String(result.reason ?? "").trim().toLowerCase();
  const reason = rawReason === GAME_END_REASONS.ABANDON
    || rawReason === GAME_END_REASONS.DECK_EMPTY
    || rawReason === GAME_END_REASONS.PILE_EMPTY
    ? rawReason
    : GAME_END_REASONS.ABANDON;
  const by = typeof result.by === "string" ? result.by : "";
  const at = typeof result.at === "number" && Number.isFinite(result.at) ? result.at : 0;

  return {
    winner,
    reason,
    by,
    at,
  };
}

function resolvePlayerOpponent(game, username) {
  if (!game || !Array.isArray(game.players)) return "";
  const players = game.players.filter((p) => typeof p === "string" && p.trim());
  if (!players.includes(username)) return "";
  return players.find((p) => p !== username) ?? "";
}

function isSocketOpen(ws) {
  return !!ws && ws.readyState === 1;
}

function isRematchAllowedForPlayer(game, game_id, meta, wsByUser, userToGame, username) {
  const opponent = resolvePlayerOpponent(game, username);
  if (!opponent) return false;
  if (!wsByUser || typeof wsByUser.get !== "function") return false;
  if (!userToGame || typeof userToGame.get !== "function") return false;
  if (String(userToGame.get(opponent) ?? "") !== String(game_id ?? "")) return false;
  if (!isSocketOpen(wsByUser.get(opponent))) return false;
  if (meta?.disconnected instanceof Set && meta.disconnected.has(opponent)) return false;
  return true;
}

function buildStateSnapshotForUser(game, username, view, { result = null, forceDisableDrag = false } = {}) {
  const tableSlotIds = getTableSlots(game);

  const table = tableSlotIds.map((slotId) =>
    slotIdToString(view === "spectator" ? slotId : mapSlotForClient(slotId, username, game))
  );

  const slots = {};
  const slot_counts = {};

  // Ordre stable (non-table puis table)
  const allSlots = game?.slots instanceof Map ? Array.from(game.slots.keys()) : [];

  const nonTable = allSlots.filter((s) => !isTableSlot(s));
  const orderedTable = tableSlotIds;

  for (const slot_id of nonTable) {
    const { slot_id: clientSlot, cards, count } = buildSlotStateForUser(game, username, slot_id, view, { forceDisableDrag });
    slots[clientSlot] = cards;
    slot_counts[clientSlot] = count;
  }

  for (const slot_id of orderedTable) {
    const { slot_id: clientSlot, cards, count } = buildSlotStateForUser(game, username, slot_id, view, { forceDisableDrag });
    slots[clientSlot] = cards;
    slot_counts[clientSlot] = count;
  }

  const turn = buildTurnPayload(game.turn, { includeEmpty: false });

  return {
    view, // "player" | "spectator"
    table, // ["0:TABLE:1","0:TABLE:2",...]
    slots, // { "1:HAND:1":[...], "0:PILE:1":[...], ... }
    slot_counts, // { "1:HAND:1": 5, "1:DECK:1": 26, ... }
    turn, // { current, turnNumber } | null
    result, // { winner, reason, by, at } | null
  };
}

/* =========================
   EMIT PRIMITIVES
========================= */

export function emitSlotState(game, recipients, wsByUser, sendEvtSocket, { slot_id, view = "player" }) {
  if (!wsByUser || typeof wsByUser.get !== "function") return;

  for (const username of recipients) {
    const ws = wsByUser.get(username);
    if (!ws) continue;

    const payload = buildSlotStateForUser(game, username, slot_id, view);
    sendEvtSocket(ws, "slot_state", payload);
  }
}

export function emitFullState(game, username, wsByUser, sendEvtSocket, { view = "player", gameMeta = null, game_id = "" } = {}) {
  if (!wsByUser || typeof wsByUser.get !== "function") return;

  const ws = wsByUser.get(username);
  if (!ws) return;

  let result = null;
  let forceDisableDrag = !!game?.turn?.paused;
  if (gameMeta && game_id) {
    const meta = gameMeta.get(game_id) || {};
    if (meta.result) {
      result = publicGameEndResult(meta.result);
      if (view === "player") {
        result.rematch_allowed = isRematchAllowedForPlayer(
          game,
          game_id,
          meta,
          wsByUser,
          userToGame,
          username
        );
      }
    }
  }

  const snapshot = buildStateSnapshotForUser(game, username, view, { result, forceDisableDrag });

  sendEvtSocket(ws, "state_snapshot", snapshot);
}

/**
 * Notifier haut-niveau (réduit les duplications d'envoi).
 * - start_game
 * - state_snapshot à l'audience (joueurs + spectateurs)
 * - game_end idempotent (émission unique à la création du result)
 */
export function createGameNotifier({
  state = null,
  games = state?.games,
  gameMeta = state?.gameMeta,
  gameSpectators = state?.gameSpectators,
  wsByUser = state?.wsByUser,
  userToGame = state?.userToGame,
  sendEvtSocket,
  sendEvtUser,
}) {
  /**
   * Envoie start_game à un user (joueur ou spectateur).
   * R9.6: assure l'existence de gameMeta dès start_game.
   */
  function emitStartGameToUser(username, game_id, { spectator = false } = {}) {
    const game = games.get(game_id);
    if (!game) return false;

    // ✅ meta existe dès le start_game (stabilise l'init / end / dedupe)
    ensureGameMeta(gameMeta, game_id, { initialSent: !!game.turn });

    sendEvtUser(username, "start_game", {
      game_id,
      players: game.players,
      spectator: !!spectator,
    });
    return true;
  }

  /**
   * Snapshot complet à tous (joueurs + spectateurs).
   * R10.6: reason + meta.lastSnapshot + meta.snapshotSeq + dev trace
   * R9: reset dedupe centralisé (slot_sig/turn_sig) avant l'envoi.
   *
   * On passe gameMeta + game_id à emitFullState pour :
   * - injecter result dans le snapshot
   * - (éventuellement) compléter la logique de reset côté emitFullState
   */
  function emitSnapshotsToAudience(game_id, { reason = "snapshot" } = {}) {
    const game = games.get(game_id);
    if (!game) return false;

    const meta = ensureGameMeta(gameMeta, game_id, { initialSent: !!game.turn });

    // ✅ compteur snapshot (diagnostic doubles snapshots)
    meta.snapshotSeq = (meta.snapshotSeq || 0) + 1;

    // ✅ dernière cause snapshot (debug via __ctx / dump state)
    meta.lastSnapshot = {
      seq: meta.snapshotSeq,
      at: Date.now(),
      reason: String(reason || "snapshot"),
    };

    // ✅ trace dev (sans toucher au protocole)
    if (process.env.DEBUG_TRACE === "1") {
      console.log("[TRACE]", `snapshot#${meta.snapshotSeq}`, {
        game_id,
        reason: meta.lastSnapshot.reason,
        players: game.players?.length ?? 0,
        spectators: gameSpectators.get(game_id)?.size ?? 0,
        initialSent: !!meta.initialSent,
        hasResult: !!meta.result,
      });
    }

    // ✅ reset dedupe centralisé: snapshot = resync client => réarmer les signatures
    meta.slot_sig = Object.create(null);
    meta.turn_sig = "";
    gameMeta.set(game_id, meta);

    // joueurs
    for (const p of game.players) {
      emitFullState(game, p, wsByUser, sendEvtSocket, { view: "player", gameMeta, game_id });
    }

    // spectateurs
    const specs = gameSpectators.get(game_id);
    if (specs && specs.size) {
      for (const s of specs) {
        emitFullState(game, s, wsByUser, sendEvtSocket, { view: "spectator", gameMeta, game_id });
      }
    }

    return true;
  }

  /**
   * Crée/normalise meta.result et émet "game_end" une seule fois
   * (uniquement quand result vient d'être créé).
   *
   * @returns {{payload: object|null, created: boolean}}
   */
  function emitGameEndOnce(game_id, patch, { exclude = [] } = {}) {
    const game = games.get(game_id);
    if (!game) return { payload: null, created: false };

    const meta = ensureGameMeta(gameMeta, game_id, { initialSent: true });
    const { result, created } = ensureGameResult(meta, patch);

    const payload = { game_id, ...publicGameEndResult(result) };
    if (!created) return { payload, created: false };

    const excludeSet = new Set((exclude || []).filter(Boolean));

    for (const p of game.players) {
      if (excludeSet.has(p)) continue;
      sendEvtUser(p, "game_end", {
        ...payload,
        rematch_allowed: isRematchAllowedForPlayer(
          game,
          game_id,
          meta,
          wsByUser,
          userToGame,
          p
        ),
      });
    }

    const specs = gameSpectators.get(game_id);
    if (specs && specs.size) {
      for (const s of specs) {
        if (excludeSet.has(s)) continue;
        sendEvtUser(s, "game_end", { ...payload, rematch_allowed: false });
      }
    }

    return { payload, created: true };
  }
  return { emitStartGameToUser, emitSnapshotsToAudience, emitGameEndOnce };
}
