// helpers/tableHelper.js - Table slot creation/deletion operations

import { SlotId, SLOT_TYPES } from "../constants/slots.js";
import { createEmptySlots } from "../factory/createGame.js";
import { debugLog } from "./debugHelpers.js";

function ensureSlots(game) {
  if (!(game?.slots instanceof Map)) {
    game.slots = createEmptySlots();
  }
}

function addTableSlot(game) {
  ensureSlots(game);

  let maxIndex = 0;
  for (const [slotId] of game.slots) {
    if (!(slotId instanceof SlotId) || slotId.type !== SLOT_TYPES.TABLE) continue;
    if (slotId.index > maxIndex) maxIndex = slotId.index;
  }

  const nextIndex = maxIndex + 1;
  const newSlot = SlotId.create(0, SLOT_TYPES.TABLE, nextIndex);
  game.slots.set(newSlot, []);
  debugLog("[TABLE] ADD_SLOT", { created: String(newSlot), nextIndex });
  return newSlot;
}

function removeTableslot(game, index) {
  ensureSlots(game);
  const slotId = SlotId.create(0, SLOT_TYPES.TABLE, index);
  const removed = game.slots.delete(slotId);
  if (removed) {
    debugLog("[TABLE] REMOVE_SLOT", { removed: String(slotId), index });
  }
  return removed;
}

export { addTableSlot, removeTableslot };
