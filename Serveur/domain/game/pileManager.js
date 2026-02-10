// domain/game/pileManager.js - Pile and refill operations

import { shuffle } from "./state.js";
import {
  SlotId,
  makePlayerSlotId,
  SLOT_TYPES,
  getSlotStack,
  drawTop,
  putTop,
  putBottom,
  getTableSlots,
} from "./SlotManager.js";
 
/**
 * Refill an empty hand from the pile.
 * @param {Object} game Game state
 * @param {string} player Player username
 * @param {number} maxCards Max hand size (default: 5)
 * @returns {Array<{slotId: Object, cardId: string}>}
 */
export function refillEmptyHandSlotsFromPile(game, player, maxCards = 5) {
  const playerIndex = game.players.indexOf(player);
  if (playerIndex === -1) return [];
  const slotPlayerIndex = playerIndex + 1;

  const handSlot = makePlayerSlotId(slotPlayerIndex, SLOT_TYPES.HAND, 1);
  const handStack = getSlotStack(game, handSlot);
  const pileSlot = SlotId.create(0, SLOT_TYPES.PILE, 1);

  const given = [];
  const needed = maxCards - handStack.length;

  for (let i = 0; i < needed; i++) {
    const cardId = drawTop(game, pileSlot);
    if (!cardId) break;
    putTop(game, handSlot, cardId);
    given.push({ slotId: handSlot, cardId });
  }

  return given;
}

/**
 * Recycle full table stacks (12 cards) under the pile.
 * - For each TABLE slot that has exactly 12 cards:
 *   1) shuffle its ids
 *   2) push cards to pile bottom
 *   3) clear the TABLE slot
 *
 * @param {Object} game Game state
 * @returns {Object} {recycledSlots, pileTopChanged}
 */
export function recycleFullTableSlotsToPile(game) {
  const recycledSlots = [];
  if (!game || !game.slots) {
    return { recycledSlots, pileTopChanged: false };
  }

  const pileSlot = SlotId.create(0, SLOT_TYPES.PILE, 1);
  const pile = getSlotStack(game, pileSlot);

  // Top card is the last index.
  const prevTop = pile.length ? pile[pile.length - 1] : null;

  for (const slotId of getTableSlots(game)) {
    const content = getSlotStack(game, slotId);
    if (!Array.isArray(content)) continue;
    if (content.length !== 12) continue;

    const ids = content.slice();
    shuffle(ids);

    // Pile bottom is index 0.
    for (const id of ids) {
      if (typeof id === "string") putBottom(game, pileSlot, id);
    }

    game.slots.delete(slotId);
    recycledSlots.push(slotId);

    console.log("[PILE] RECYCLE_TABLE_TO_PILE", {
      slotId,
      count: ids.length,
      pileLength: pile.length,
    });
  }

  const newTop = pile.length ? pile[pile.length - 1] : null;
  const pileTopChanged = newTop !== prevTop;

  return { recycledSlots, pileTopChanged };
}
