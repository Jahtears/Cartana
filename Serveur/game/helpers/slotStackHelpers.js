import { SlotId, SLOT_TYPES } from "../constants/slots.js";

function isCardId(value) {
  return typeof value === "string" && value.length > 0;
}

function isHandSlotId(slotId) {
  return slotId instanceof SlotId && slotId.type === SLOT_TYPES.HAND;
}

function countCards(stack) {
  if (!Array.isArray(stack) || stack.length === 0) return 0;
  let count = 0;
  for (const id of stack) {
    if (isCardId(id)) count++;
  }
  return count;
}

function findFirstEmptyHandCell(stack) {
  if (!Array.isArray(stack)) return -1;
  for (let i = 0; i < stack.length; i++) {
    if (!isCardId(stack[i])) return i;
  }
  return -1;
}

function fillFirstEmptyHandCell(stack, cardId) {
  const emptyIndex = findFirstEmptyHandCell(stack);
  if (emptyIndex === -1) return false;
  stack[emptyIndex] = cardId;
  return true;
}

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
  if (!isCardId(cardId)) return;
  const stack = getSlotStack(game, slotId, initSlotsFactory);
  if (isHandSlotId(slotId) && fillFirstEmptyHandCell(stack, cardId)) return;
  stack.push(cardId);
}

function putBottom(game, slotId, cardId, initSlotsFactory = null) {
  if (!isCardId(cardId)) return;
  const stack = getSlotStack(game, slotId, initSlotsFactory);
  if (isHandSlotId(slotId) && fillFirstEmptyHandCell(stack, cardId)) return;
  stack.unshift(cardId);
}

function drawTop(game, slotId, initSlotsFactory = null) {
  const stack = getSlotStack(game, slotId, initSlotsFactory);
  if (isHandSlotId(slotId)) {
    for (let i = stack.length - 1; i >= 0; i--) {
      if (!isCardId(stack[i])) continue;
      const cardId = stack[i];
      stack[i] = null;
      return cardId;
    }
    return null;
  }
  return stack.length ? stack.pop() : null;
}

function removeCardFromSlot(game, slotId, cardId, initSlotsFactory = null) {
  const stack = getSlotStack(game, slotId, initSlotsFactory);
  const idx = stack.indexOf(cardId);
  if (idx === -1) return false;
  if (isHandSlotId(slotId)) {
    stack[idx] = null;
    return true;
  }
  stack.splice(idx, 1);
  return true;
}

function getSlotCount(game, slotId, initSlotsFactory = null) {
  const stack = getSlotStack(game, slotId, initSlotsFactory);
  return isHandSlotId(slotId) ? countCards(stack) : stack.length;
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
