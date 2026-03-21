import { SlotId, SLOT_TYPES } from '../constants/slots.js';

const HAND_FIXED_SIZE = 5;

function isCardId(value) {
  return typeof value === 'string' && value.length > 0;
}

function isHandSlotId(slotId) {
  return slotId instanceof SlotId && slotId.type === SLOT_TYPES.HAND;
}

function countCards(stack) {
  if (!Array.isArray(stack) || stack.length === 0) {
    return 0;
  }
  let count = 0;
  for (const id of stack) {
    if (isCardId(id)) {
      count++;
    }
  }
  return count;
}

function findFirstEmptyHandCell(stack) {
  if (!Array.isArray(stack)) {
    return -1;
  }
  for (let i = 0; i < stack.length; i++) {
    if (!isCardId(stack[i])) {
      return i;
    }
  }
  if (stack.length < HAND_FIXED_SIZE) {
    return stack.length;
  }
  return -1;
}

function fillFirstEmptyHandCell(stack, cardId) {
  const emptyIndex = findFirstEmptyHandCell(stack);
  if (emptyIndex === -1) {
    return false;
  }
  stack[emptyIndex] = cardId;
  return true;
}

function ensureSlotStorage(game, initSlotsFactory = null) {
  if (!game) {
    return null;
  }

  if (!(game.slots instanceof Map)) {
    game.slots = typeof initSlotsFactory === 'function' ? initSlotsFactory() : new Map();
  }

  return game.slots;
}

function getSlotStack(game, slotId, initSlotsFactory = null) {
  const slots = ensureSlotStorage(game, initSlotsFactory);
  if (!(slots instanceof Map)) {
    return [];
  }

  if (!slots.has(slotId) && slotId instanceof SlotId && slotId.type === SLOT_TYPES.TABLE) {
    slots.set(slotId, []);
  }

  return slots.get(slotId) || [];
}

function putCardtoHandFromPile(game, slotId, cardId, initSlotsFactory = null) {
  if (!isHandSlotId(slotId) || !isCardId(cardId)) {
    return false;
  }
  const stack = getSlotStack(game, slotId, initSlotsFactory);
  return fillFirstEmptyHandCell(stack, cardId);
}

function removeCardFromSlot(game, slotId, cardId, initSlotsFactory = null) {
  const stack = getSlotStack(game, slotId, initSlotsFactory);
  const idx = stack.indexOf(cardId);
  if (idx === -1) {
    return false;
  }

  if (isHandSlotId(slotId)) {
    stack[idx] = '';
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

function getHandSize(game, playerIndex) {
  const handSlot = SlotId.create(playerIndex, SLOT_TYPES.HAND, 1);
  return getSlotCount(game, handSlot);
}

function getTableSlots(game, initSlotsFactory = null) {
  const slots = ensureSlotStorage(game, initSlotsFactory);
  if (!(slots instanceof Map)) {
    return [];
  }

  const tableSlots = [];
  for (const [slotId] of slots) {
    if (!(slotId instanceof SlotId) || slotId.type !== SLOT_TYPES.TABLE) {
      continue;
    }
    tableSlots.push(slotId);
  }

  tableSlots.sort((a, b) => a.index - b.index);
  return tableSlots;
}

function hasCardInSlot(game, slotId, cardId) {
  if (!game || !game.slots) {
    return false;
  }
  const slotContent = getSlotStack(game, slotId);
  return slotContent.includes(cardId);
}

function isOwnerForSlot(game, slotId, username) {
  const userArrayIndex = game.players.indexOf(username);
  if (userArrayIndex === -1) {
    return false;
  }

  const userPlayerIndex = userArrayIndex + 1;

  if (!(slotId instanceof SlotId)) {
    return false;
  }
  if (slotId.player === 0) {
    return false;
  }
  return slotId.player === userPlayerIndex;
}

function slotIdToString(slotId) {
  if (slotId instanceof SlotId) {
    return slotId.toString();
  }
  return String(slotId);
}

export {
  ensureSlotStorage,
  getHandSize,
  getSlotCount,
  getSlotStack,
  getTableSlots,
  hasCardInSlot,
  isOwnerForSlot,
  isSlotEmpty,
  putCardtoHandFromPile,
  removeCardFromSlot,
  slotIdToString,
};
