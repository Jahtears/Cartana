import { SlotId, SLOT_TYPES } from "../constants/slots.js";

function ensureSlotStorage(game, initSlotsFactory = null) {
  if (!game) return null;

  if (!(game.slots instanceof Map)) {
    game.slots = typeof initSlotsFactory === "function"
      ? initSlotsFactory()
      : new Map();
  }

  return game.slots;
}

function getSlotStack(game, slotId, initSlotsFactory = null) {
  const slots = ensureSlotStorage(game, initSlotsFactory);
  if (!(slots instanceof Map)) return [];

  if (!slots.has(slotId) && slotId instanceof SlotId && slotId.type === SLOT_TYPES.TABLE) {
    slots.set(slotId, []);
  }

  return slots.get(slotId) || [];
}

function putTop(game, slotId, cardId, initSlotsFactory = null) {
  if (!cardId) return;
  getSlotStack(game, slotId, initSlotsFactory).push(cardId);
}

function putBottom(game, slotId, cardId, initSlotsFactory = null) {
  if (!cardId) return;
  getSlotStack(game, slotId, initSlotsFactory).unshift(cardId);
}

function drawTop(game, slotId, initSlotsFactory = null) {
  const stack = getSlotStack(game, slotId, initSlotsFactory);
  return stack.length ? stack.pop() : null;
}

function removeCardFromSlot(game, slotId, cardId, initSlotsFactory = null) {
  const stack = getSlotStack(game, slotId, initSlotsFactory);
  const idx = stack.indexOf(cardId);
  if (idx === -1) return false;
  stack.splice(idx, 1);
  return true;
}

function getSlotCount(game, slotId, initSlotsFactory = null) {
  return getSlotStack(game, slotId, initSlotsFactory).length;
}

function isSlotEmpty(game, slotId, initSlotsFactory = null) {
  return getSlotCount(game, slotId, initSlotsFactory) === 0;
}

export {
  drawTop,
  ensureSlotStorage,
  getSlotCount,
  getSlotStack,
  isSlotEmpty,
  putBottom,
  putTop,
  removeCardFromSlot,
};
