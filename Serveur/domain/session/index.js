import { ensureGameMeta, ensureGameResult } from "../game/meta.js";
import {
  mapSlotForClient,
  isOwnerForSlot,
  buildCardData,
  slotIdToNewString,
} from "../game/slots.js";
import { getTableSlots, isTableSlot, getSlotStack, SLOT_TYPES, SlotId } from "../game/SlotManager.js";
import { findCardById } from "../game/state.js";

/* =========================
   HELPERS FOR SLOT STATE
========================= */

function getSlotType(slot_id) {
  if (slot_id instanceof SlotId) return slot_id.type;
  if (typeof slot_id === "string") {
    // New format: "0:TYPE:index" (shared=0, players=1/2)
    const match = slot_id.match(/^(\d+):([A-Z]+):(\d+)$/);
    if (match) {
      const t = match[2];
      if (SLOT_TYPES[t]) return SLOT_TYPES[t];
    }
  }
  return null;
}

function isTableSlotLike(slot_id) {
  if (isTableSlot(slot_id)) return true;
  if (typeof slot_id === "string") return /^\d+:TABLE:\d+$/.test(slot_id);
  return false;
}

function buildSlotStateForUser(game, username, slot_id, view) {
  const disableDrag = view === "spectator";

  const clientSlot = slotIdToNewString(
    view === "spectator" ? slot_id : mapSlotForClient(slot_id, username, game)
  );

  const isOwner = view === "spectator"
    ? false
    : isOwnerForSlot(game, slot_id, username);

  const cards = [];

  let stack = [];
  if (slot_id instanceof SlotId) {
    stack = getSlotStack(game, slot_id);
  } else if (game?.slots instanceof Map) {
    const v = game.slots.get(slot_id);
    stack = Array.isArray(v) ? v : (v ? [v] : []);
  } else {
    const v = game?.slots?.[slot_id];
    stack = Array.isArray(v) ? v : (v ? [v] : []);
  }

  if (!stack.length) return { slot_id: clientSlot, cards };

  const slotType = getSlotType(slot_id);

  let ids = [];
  if (slotType === SLOT_TYPES.HAND) {
    // Main: tout le stack (toutes les cartes visibles côté owner)
    ids = [...stack];
  } else if (slotType === SLOT_TYPES.PILE || slotType === SLOT_TYPES.DECK) {
    // Pile & Deck: top uniquement (évite les leaks)
    ids = stack.length ? [stack[stack.length - 1]] : [];
  } else if (slotType === SLOT_TYPES.TABLE) {
    // Table: top uniquement
    ids = stack.length ? [stack[stack.length - 1]] : [];
  } else {
    // Bench: tout le stack (toutes affichées)
    ids = [...stack];
  }

  for (let i = 0; i < ids.length; i++) {
    const card = findCardById(game, ids[i]);
    if (!card) continue;

    const payload = buildCardData(card, clientSlot, isOwner, disableDrag);

    // ✅ ADAPTATION: Gestion du drag selon le type de slot
    if (slotType === SLOT_TYPES.HAND) {
      // Main: toutes les cartes draggable par owner
      payload.draggable = payload.draggable;
    } else if (slotType === SLOT_TYPES.DECK) {
      // Deck: seule la top (dernier index dans ids, qui ne contient que le top)
      payload.draggable = payload.draggable;
    } else if (slotType === SLOT_TYPES.BENCH) {
      // Bench: seule la bot (index 0 du stack original) draggable
      const isTop = ids[i] === stack[stack.length - 1];
      payload.draggable = payload.draggable && isTop;
    } else if (slotType === SLOT_TYPES.TABLE || slotType === SLOT_TYPES.PILE) {
      // Table et Pile: jamais draggable
      payload.draggable = false;
    }

    cards.push(payload);
  }

  return { slot_id: clientSlot, cards };
}

function buildStateSnapshotForUser(game, username, view, { result = null } = {}) {
  const tableSlotIds = getTableSlots(game);

  const table = tableSlotIds.map((slotId) =>
    slotIdToNewString(view === "spectator" ? slotId : mapSlotForClient(slotId, username, game))
  );

  const slots = {};

  // Ordre stable (non-T puis T)
  const allSlots = game?.slots instanceof Map
    ? Array.from(game.slots.keys())
    : Object.keys(game?.slots || {});

  const nonT = allSlots.filter(s => !isTableSlotLike(s));
  const T = tableSlotIds;

  for (const slot_id of nonT) {
    const { slot_id: clientSlot, cards } = buildSlotStateForUser(game, username, slot_id, view);
    slots[clientSlot] = cards;
  }

  for (const slot_id of T) {
    const { slot_id: clientSlot, cards } = buildSlotStateForUser(game, username, slot_id, view);
    slots[clientSlot] = cards;
  }

  const turn = game.turn
    ? {
        current: game.turn.current,
        turnNumber: game.turn.number,
        endsAt: game.turn.endsAt ?? null,
        durationMs: game.turn.durationMs ?? null,
        serverNow: Date.now(),
      }
    : null;

  return {
    view, // "player" | "spectator"
    table, // ["0:TABLE:1","0:TABLE:2",...]
    slots, // { "1:HAND:1":[...], "0:PILE:1":[...], ... }
    turn, // { current, turnNumber } | null
    result, // { winner, reason, by, at } | null
  };
}

/* =========================
   EMIT PRIMITIVES
========================= */

export function emitSlotState(game, recipients, wsByUser, sendEvent, { slot_id, view = "player" }) {
  if (!wsByUser || typeof wsByUser.get !== "function") return;

  for (const username of recipients) {
    const ws = wsByUser.get(username);
    if (!ws) continue;

    const payload = buildSlotStateForUser(game, username, slot_id, view);
    sendEvent(ws, "slot_state", payload);
  }
}

export function emitFullState(game, username, wsByUser, sendEvent, { view = "player", gameMeta = null, game_id = "" } = {}) {
  if (!wsByUser || typeof wsByUser.get !== "function") return;

  const ws = wsByUser.get(username);
  if (!ws) return;

  let result = null;
  if (gameMeta && game_id) {
    const meta = gameMeta.get(game_id) || {};
    result = meta.result ?? null;
  }

  const snapshot = buildStateSnapshotForUser(game, username, view, { result });

  sendEvent(ws, "state_snapshot", snapshot);
}

/**
 * Notifier haut-niveau (réduit les duplications d'envoi).
 * - start_game
 * - state_snapshot à l'audience (joueurs + spectateurs)
 * - game_end idempotent (émission unique à la création du result)
 */
export function createGameNotifier({
  games,
  gameMeta,
  gameSpectators,
  wsByUser,
  sendEvent,
  sendEventToUser,
}) {
  /**
   * Envoie start_game à un user (joueur ou spectateur).
   * R9.6: assure l'existence de gameMeta dès start_game.
   */
  function emitStartGameToUser(username, game_id, { spectator = false } = {}) {
    const game = games.get(game_id);
    if (!game) return false;

    // ✅ meta existe dès le start_game (stabilise ready_for_game / end / dedupe)
    ensureGameMeta(gameMeta, game_id, { initialSent: !!game.turn });

    sendEventToUser(username, "start_game", {
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
      emitFullState(game, p, wsByUser, sendEvent, { view: "player", gameMeta, game_id });
    }

    // spectateurs
    const specs = gameSpectators.get(game_id);
    if (specs && specs.size) {
      for (const s of specs) {
        emitFullState(game, s, wsByUser, sendEvent, { view: "spectator", gameMeta, game_id });
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

    const payload = { game_id, ...result };
    if (!created) return { payload, created: false };

    const excludeSet = new Set((exclude || []).filter(Boolean));

    for (const p of game.players) {
      if (!excludeSet.has(p)) sendEventToUser(p, "game_end", payload);
    }

    const specs = gameSpectators.get(game_id);
    if (specs && specs.size) {
      for (const s of specs) {
        if (!excludeSet.has(s)) sendEventToUser(s, "game_end", payload);
      }
    }

    return { payload, created: true };
  }
  return { emitStartGameToUser, emitSnapshotsToAudience, emitGameEndOnce };
}
