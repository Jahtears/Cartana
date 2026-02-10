// turn.js - Turn system

import {
  getSlotStack,
  makePlayerSlotId,
  getOrCreateTableSlotWithFlag,
  cleanupEmptyTableSlots,
  ensureOneEmptyTableSlot,
  removeCardFromSlot,
  putTop,
  SLOT_TYPES,
} from "./SlotManager.js";
import {
  refillEmptyHandSlotsFromPile,
  recycleFullTableSlotsToPile,
} from "./pileManager.js";
import {
  TURN_MS,
  isTurnExpired,
  startTurnClock,
} from "./turnClock.js";
import {
  compareCardsByTurnValue,
  findAceCardInHand,
} from "./slotValidators.js";

/**
 * Determine who starts:
 * - compare each player's deck top card (index -1)
 * - if tied, compare index -2
 * - if still tied, fallback to player[0]
 */
export function initTurnForGame(game) {
  const p1 = game.players[0];
  const p2 = game.players[1];

  // SlotManager expects playerIndex 1 or 2.
  const d1Ids = getSlotStack(game, makePlayerSlotId(1, SLOT_TYPES.DECK, 1));
  const d2Ids = getSlotStack(game, makePlayerSlotId(2, SLOT_TYPES.DECK, 1));

  const top1Id = d1Ids.length ? d1Ids[d1Ids.length - 1] : null;
  const top2Id = d2Ids.length ? d2Ids[d2Ids.length - 1] : null;

  const top1 = top1Id ? (game.cardsById?.[top1Id] ?? null) : null;
  const top2 = top2Id ? (game.cardsById?.[top2Id] ?? null) : null;

  let cmp = compareCardsByTurnValue(top1, top2);

  if (cmp === 0) {
    const top1bId = d1Ids.length > 1 ? d1Ids[d1Ids.length - 2] : null;
    const top2bId = d2Ids.length > 1 ? d2Ids[d2Ids.length - 2] : null;

    const top1b = top1bId ? (game.cardsById?.[top1bId] ?? null) : null;
    const top2b = top2bId ? (game.cardsById?.[top2bId] ?? null) : null;

    cmp = compareCardsByTurnValue(top1b, top2b);
  }

  const starter = (cmp >= 0) ? p1 : p2;
  game.turn = { current: starter, number: 1 };
  startTurnClock(game.turn, Date.now(), TURN_MS);

  console.log("[TURN] INIT", {
    starter,
    p1_top: top1 ? top1.value : null,
    p2_top: top2 ? top2.value : null,
  });

  return { starter, reason: "A vous de commencer" };
}

/**
 * End actor turn after BENCH play:
 * refill opponent hand if empty, then switch turn.
 */
export function endTurnAfterBenchPlay(game, actor) {
  const recycled = recycleFullTableSlotsToPile(game);
  const next = actor === game.players[0] ? game.players[1] : game.players[0];

  if (recycled?.recycledSlots?.length) {
    getOrCreateTableSlotWithFlag(game);
    cleanupEmptyTableSlots(game);
  }

  const given = refillEmptyHandSlotsFromPile(game, next, 5);

  game.turn = game.turn || { current: next, number: 1 };
  game.turn.current = next;
  game.turn.number = (game.turn.number ?? 1) + 1;
  startTurnClock(game.turn, Date.now(), TURN_MS);

  console.log("[TURN] SWITCH", { endedBy: actor, next, turnNumber: game.turn.number });

  return { next, given, recycled };
}

/**
 * Try to expire current turn when timer elapsed.
 * - auto-play an Ace from hand to table if available
 * - run canonical end-of-turn pipeline
 * - reset timer from provided timestamp
 *
 * @returns {false|Object}
 */
export function tryExpireTurn(game, now = Date.now()) {
  const t = game?.turn;
  if (!t) return false;
  if (!isTurnExpired(t, now)) return false;

  const prev = String(t.current ?? "").trim();
  if (!prev) return false;

  let playedAce = false;
  let aceFrom = null;
  let aceTo = null;
  let tableSyncNeeded = false;

  const prevPlayerArrayIndex = game.players.indexOf(prev);
  const handSlot = prevPlayerArrayIndex === -1
    ? null
    : makePlayerSlotId(prevPlayerArrayIndex + 1, SLOT_TYPES.HAND, 1);
  const ace = handSlot ? findAceCardInHand(game, handSlot, 5) : null;
  if (ace) {
    const { slotId: tableSlot, created } = getOrCreateTableSlotWithFlag(game);
    const removed = removeCardFromSlot(game, ace.slotId, ace.cardId);
    if (removed) {
      putTop(game, tableSlot, ace.cardId);
      playedAce = true;
      aceFrom = ace.slotId;
      aceTo = tableSlot;
      tableSyncNeeded = !!created;
      if (ensureOneEmptyTableSlot(game)) tableSyncNeeded = true;

      console.log("[TURN] TIMEOUT_AUTO_ACE", { prev, from: aceFrom, to: aceTo });
    }
  }

  const { next, given, recycled } = endTurnAfterBenchPlay(game, prev);

  // Keep external ticker timestamp as reference.
  startTurnClock(game.turn, now, TURN_MS);

  const result = {
    expired: true,
    prev,
    next,
    given,
    recycled,
    playedAce,
    aceFrom,
    aceTo,
    tableSyncNeeded,
    endsAt: game.turn.endsAt,
    durationMs: game.turn.durationMs,
    turnNumber: game.turn.number,
  };

  console.log("[TURN] TIMEOUT_EXPIRED", {
    prev: result.prev,
    next: result.next,
    playedAce: result.playedAce,
    turnNumber: result.turnNumber,
  });

  return result;
}
