// helpers/tableHelper.js - Table and slot topology operations

import { SlotId, SLOT_TYPES } from "../constants/slots.js";
import { createEmptySlots } from "../builders/gameBuilder.js";
import { isSlotEmpty } from "./slotStackHelpers.js";
import { debugLog } from "./debugHelpers.js";

function ensureSlots(game) {
  if (!game.slots) {
    game.slots = createEmptySlots();
  }
}

function getTableTopology(game) {
  ensureSlots(game);

  const tableSlots = [];
  let maxIndex = 0;
  let firstEmpty = null;

  for (const [slotId] of game.slots) {
    if (!(slotId instanceof SlotId) || slotId.type !== SLOT_TYPES.TABLE) continue;

    tableSlots.push(slotId);
    if (slotId.index > maxIndex) maxIndex = slotId.index;

    if (isSlotEmpty(game, slotId)) {
      if (!firstEmpty || slotId.index < firstEmpty.index) {
        firstEmpty = slotId;
      }
    }
  }

  tableSlots.sort((a, b) => a.index - b.index);
  return { tableSlots, maxIndex, firstEmpty };
}

function getTableSlots(game) {
  return getTableTopology(game).tableSlots;
}

function addTableSlot(game) {
  ensureSlots(game);
  const { maxIndex } = getTableTopology(game);
  const nextIndex = maxIndex + 1;
  const newSlot = SlotId.create(0, SLOT_TYPES.TABLE, nextIndex);
  game.slots.set(newSlot, []);
  debugLog("[TABLE] ADD_SLOT", {
    created: String(newSlot),
    nextIndex,
  });
  return newSlot;
}

function ensureEmptyTableSlot(game) {
  ensureSlots(game);
  const { firstEmpty } = getTableTopology(game);
  if (firstEmpty) {
    debugLog("[TABLE] ENSURE_EMPTY_REUSE", {
      slot: String(firstEmpty),
    });
    return { slotId: firstEmpty, created: false };
  }

  const slotId = addTableSlot(game);
  debugLog("[TABLE] ENSURE_EMPTY_CREATE", {
    slot: String(slotId),
  });
  return { slotId, created: true };
}

function cleanupExtraEmptyTableSlots(game) {
  const slots = getTableSlots(game);
  const empty = slots.filter((id) => isSlotEmpty(game, id));
  if (empty.length <= 1) return [];

  const toDelete = empty.slice(1);
  toDelete.forEach((id) => game.slots.delete(id));
  debugLog("[TABLE] CLEANUP_EXTRA_EMPTY", {
    removed: toDelete.map((id) => String(id)),
    keep: String(empty[0]),
  });
  return toDelete;
}

export {
  getTableSlots,
  ensureEmptyTableSlot,
  cleanupExtraEmptyTableSlots,
};
