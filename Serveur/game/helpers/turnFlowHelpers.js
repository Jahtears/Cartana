// helpers/turnFlowHelpers.js - Turn start/end/timeout flow helpers

import { SLOT_TYPES, SlotId } from "../constants/slots.js";
import {
  DEFAULT_HAND_SIZE,
  INITIAL_TURN_NUMBER,
} from "../constants/turnFlow.js";
import {
  TURN_MS,
  isTurnExpired,
  startTurnClock,
} from "../turnClock.js";
import {
  compareCardsByTurnValue,
  findAceCardInHand,
} from "./cardHelpers.js";
import {
  cleanupExtraEmptyTableSlots,
  ensureEmptyTableSlot,
} from "./tableHelper.js";
import {
  getSlotStack,
  putTop,
  removeCardFromSlot,
} from "./slotStackHelpers.js";
import {
  recycleFullTableSlotsToPile,
  refillEmptyHandSlotsFromPile,
} from "./pileFlowHelpers.js";
import { debugLog } from "./debugHelpers.js";
import { INLINE_MESSAGE } from "../constants/inlineMessages.js";

const TURN_FLOW_MESSAGES = {
  START: INLINE_MESSAGE.TURN_START_FIRST,
  TIMEOUT: INLINE_MESSAGE.TURN_TIMEOUT,
  TURN_START: INLINE_MESSAGE.TURN_START,
};

function initTurnForGame(game) {
  const p1 = game.players[0];
  const p2 = game.players[1];

  const d1Ids = getSlotStack(game, SlotId.create(1, SLOT_TYPES.DECK, 1));
  const d2Ids = getSlotStack(game, SlotId.create(2, SLOT_TYPES.DECK, 1));

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

  const starter = cmp >= 0 ? p1 : p2;
  game.turn = { current: starter, number: INITIAL_TURN_NUMBER };
  startTurnClock(game.turn, Date.now(), TURN_MS);

  debugLog("[TURN] INIT", {
    starter,
    p1_top: top1 ? top1.value : null,
    p2_top: top2 ? top2.value : null,
  });

  return { starter, reason: TURN_FLOW_MESSAGES.START };
}

function endTurnAfterBenchPlay(game, actor) {
  const recycled = recycleFullTableSlotsToPile(game);
  const next = actor === game.players[0] ? game.players[1] : game.players[0];

  if (recycled?.recycledSlots?.length) {
    ensureEmptyTableSlot(game);
    cleanupExtraEmptyTableSlots(game);
  }

  const given = refillEmptyHandSlotsFromPile(game, next, DEFAULT_HAND_SIZE);

  game.turn = game.turn || { current: next, number: INITIAL_TURN_NUMBER };
  game.turn.current = next;
  game.turn.number = (game.turn.number ?? INITIAL_TURN_NUMBER) + 1;
  startTurnClock(game.turn, Date.now(), TURN_MS);

  debugLog("[TURN] SWITCH", { endedBy: actor, next, turnNumber: game.turn.number });

  return { next, given, recycled };
}

function tryExpireTurn(game, now = Date.now()) {
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
    : SlotId.create(prevPlayerArrayIndex + 1, SLOT_TYPES.HAND, 1);
  const ace = handSlot ? findAceCardInHand(game, handSlot, DEFAULT_HAND_SIZE) : null;
  if (ace) {
    const { slotId: tableSlot, created } = ensureEmptyTableSlot(game);
    const removed = removeCardFromSlot(game, ace.slotId, ace.cardId);
    if (removed) {
      putTop(game, tableSlot, ace.cardId);
      playedAce = true;
      aceFrom = ace.slotId;
      aceTo = tableSlot;
      tableSyncNeeded = !!created;
      if (ensureEmptyTableSlot(game).created) tableSyncNeeded = true;

      debugLog("[TURN] TIMEOUT_AUTO_ACE", { prev, from: aceFrom, to: aceTo });
    }
  }

  const { next, given, recycled } = endTurnAfterBenchPlay(game, prev);

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

  debugLog("[TURN] TIMEOUT_EXPIRED", {
    prev: result.prev,
    next: result.next,
    playedAce: result.playedAce,
    turnNumber: result.turnNumber,
  });

  return result;
}

export {
  endTurnAfterBenchPlay,
  initTurnForGame,
  TURN_FLOW_MESSAGES,
  tryExpireTurn,
};
