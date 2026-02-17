// helpers/pileFlowHelpers.js - Pile refill/recycle flow helpers

import { SLOT_TYPES, SlotId } from "../constants/slots.js";
import {
  DEFAULT_HAND_SIZE,
  TABLE_RECYCLE_CARD_COUNT,
} from "../constants/turnFlow.js";
import { shuffle } from "./cardHelpers.js";
import { getTableSlots } from "./tableHelper.js";
import {
  drawTop,
  getSlotCount,
  getSlotStack,
  putBottom,
  putTop,
} from "./slotStackHelpers.js";
import { getHandSize } from "./slotHelpers.js";
import { debugLog } from "./debugHelpers.js";

function refillEmptyHandSlotsFromPile(game, player, maxCards = DEFAULT_HAND_SIZE) {
  if (!game || !Array.isArray(game.players)) return [];

  const playerIndex = game.players.indexOf(player);
  if (playerIndex === -1) return [];
  const slotPlayerIndex = playerIndex + 1;

  const handSlot = SlotId.create(slotPlayerIndex, SLOT_TYPES.HAND, 1);
  const pileSlot = SlotId.create(0, SLOT_TYPES.PILE, 1);

  const given = [];
  const needed = Math.max(0, maxCards - getSlotCount(game, handSlot));

  for (let i = 0; i < needed; i++) {
    const cardId = drawTop(game, pileSlot);
    if (!cardId) break;
    putTop(game, handSlot, cardId);
    given.push({ slotId: handSlot, cardId });
  }

  return given;
}

function isHandCompletelyEmpty(game, player) {
  if (!game || !Array.isArray(game.players)) return false;

  const playerArrayIndex = game.players.indexOf(player);
  if (playerArrayIndex === -1) return false;

  return getHandSize(game, playerArrayIndex + 1) === 0;
}

function refillHandIfEmpty(game, player, handSize = DEFAULT_HAND_SIZE) {
  if (!isHandCompletelyEmpty(game, player)) return [];
  return refillEmptyHandSlotsFromPile(game, player, handSize);
}

function recycleFullTableSlotsToPile(game) {
  const recycledSlots = [];
  if (!game || !game.slots) {
    return { recycledSlots, pileTopChanged: false };
  }

  const pileSlot = SlotId.create(0, SLOT_TYPES.PILE, 1);
  const pile = getSlotStack(game, pileSlot);
  const prevTop = pile.length ? pile[pile.length - 1] : null;

  for (const slotId of getTableSlots(game)) {
    const content = getSlotStack(game, slotId);
    if (!Array.isArray(content)) continue;
    if (content.length !== TABLE_RECYCLE_CARD_COUNT) continue;

    const ids = content.slice();
    shuffle(ids);

    for (const id of ids) {
      if (typeof id === "string") putBottom(game, pileSlot, id);
    }

    game.slots.delete(slotId);
    recycledSlots.push(slotId);

    debugLog("[PILE] RECYCLE_TABLE_TO_PILE", {
      slotId,
      count: ids.length,
      pileLength: pile.length,
    });
  }

  const newTop = pile.length ? pile[pile.length - 1] : null;
  const pileTopChanged = newTop !== prevTop;

  return { recycledSlots, pileTopChanged };
}

export {
  recycleFullTableSlotsToPile,
  refillEmptyHandSlotsFromPile,
  refillHandIfEmpty,
};
