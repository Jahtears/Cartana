import { SlotId, SLOT_TYPES } from "../constants/slots.js";

const SLOT_TYPE_SET = new Set(Object.values(SLOT_TYPES));
const HAND_FIXED_SIZE = 5;

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
  if (stack.length < HAND_FIXED_SIZE) return stack.length;
  return -1;
}

function fillFirstEmptyHandCell(stack, cardId) {
  const emptyIndex = findFirstEmptyHandCell(stack);
  if (emptyIndex === -1) return false;
  stack[emptyIndex] = cardId;
  return true;
}

/* =========================
   RUNTIME (SlotId canonique)
========================= */

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

function drawCardFromHand(game, slotId, cardId, initSlotsFactory = null) {
  if (!isHandSlotId(slotId) || !isCardId(cardId)) return null;
  const stack = getSlotStack(game, slotId, initSlotsFactory);
  const idx = stack.indexOf(cardId);
  if (idx === -1) return null;
  stack[idx] = "";
  return cardId;
}

function putCardtoHandFromPile(game, slotId, cardId, initSlotsFactory = null) {
  if (!isHandSlotId(slotId) || !isCardId(cardId)) return false;
  const stack = getSlotStack(game, slotId, initSlotsFactory);
  return fillFirstEmptyHandCell(stack, cardId);
}

function removeCardFromSlot(game, slotId, cardId, initSlotsFactory = null) {
  const stack = getSlotStack(game, slotId, initSlotsFactory);
  const idx = stack.indexOf(cardId);
  if (idx === -1) return false;
  if (isHandSlotId(slotId)) {
    stack[idx] = "";
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

function isValidSlotShape(player, type, index) {
  if (!Number.isInteger(player) || player < 0) return false;
  if (!SLOT_TYPE_SET.has(type)) return false;
  if (!Number.isInteger(index) || index < 1) return false;
  return true;
}

/* =========================
   BOUNDARY (client <-> serveur)
========================= */

function parseStringSlotId(value) {
  if (!value) return null;
  const text = String(value);
  const match = text.match(/^(\d+):([A-Z]+):(\d+)$/);
  if (!match) return null;

  const player = parseInt(match[1], 10);
  const type = match[2];
  const index = parseInt(match[3], 10);
  if (!Number.isFinite(player) || !Number.isFinite(index)) return null;

  return { player, type, index };
}

function parseSlotId(slotId) {
  if (slotId instanceof SlotId) {
    if (!isValidSlotShape(slotId.player, slotId.type, slotId.index)) return null;
    return {
      playerIndex: slotId.player,
      type: slotId.type,
      number: slotId.index,
    };
  }

  const parsed = parseStringSlotId(slotId);
  if (!parsed) return null;
  if (!isValidSlotShape(parsed.player, parsed.type, parsed.index)) return null;

  return {
    playerIndex: parsed.player,
    type: parsed.type,
    number: parsed.index,
  };
}

function getHandSize(game, playerIndex) {
  const handSlot = SlotId.create(playerIndex, SLOT_TYPES.HAND, 1);
  return getSlotCount(game, handSlot);
}

function hasCardInSlot(game, slotId, cardId) {
  if (!game || !game.slots) return false;
  const slotContent = getSlotStack(game, slotId);
  return slotContent.includes(cardId);
}

function isSlotIdPresent(game, slotId) {
  if (!(game?.slots instanceof Map)) return false;
  return game.slots.has(slotId);
}

function mapSlotForClient(slotId, username, game) {
  if (slotId instanceof SlotId) {
    if (slotId.player === 0) {
      return slotIdToString(slotId);
    }

    const userArrayIndex = game.players.indexOf(username);
    if (userArrayIndex === -1) {
      return slotIdToString(slotId);
    }

    const userPlayerIndex = userArrayIndex + 1;
    const displayPlayerIndex = slotId.player === userPlayerIndex ? 1 : 2;
    return `${displayPlayerIndex}:${slotId.type}:${slotId.index}`;
  }

  return slotIdToString(slotId);
}

function isOwnerForSlot(game, slotId, username) {
  const userArrayIndex = game.players.indexOf(username);
  if (userArrayIndex === -1) return false;

  const userPlayerIndex = userArrayIndex + 1;

  if (!(slotId instanceof SlotId)) return false;
  if (slotId.player === 0) return false;
  return slotId.player === userPlayerIndex;
}

function mapSlotFromClientToServer(slotId, username, game) {
  if (!slotId || typeof slotId !== "string") return null;

  const parsedClientSlot = parseSlotId(slotId);
  if (!parsedClientSlot) return null;

  if (parsedClientSlot.playerIndex === 0) {
    const serverSlot = SlotId.create(0, parsedClientSlot.type, parsedClientSlot.number);
    if (parsedClientSlot.type !== SLOT_TYPES.PILE && parsedClientSlot.type !== SLOT_TYPES.TABLE) return null;
    return isSlotIdPresent(game, serverSlot) ? serverSlot : null;
  }

  if (parsedClientSlot.playerIndex !== 1 && parsedClientSlot.playerIndex !== 2) return null;

  const userArrayIndex = game.players.indexOf(username);
  if (userArrayIndex === -1) return null;

  const userPlayerIndex = userArrayIndex + 1;
  const serverPlayerIndex = parsedClientSlot.playerIndex === 1
    ? userPlayerIndex
    : (userPlayerIndex === 1 ? 2 : 1);

  const serverSlot = SlotId.create(serverPlayerIndex, parsedClientSlot.type, parsedClientSlot.number);
  return isSlotIdPresent(game, serverSlot) ? serverSlot : null;
}

function slotIdToString(slotId) {
  if (slotId instanceof SlotId) {
    return slotId.toString();
  }
  return String(slotId);
}

export {
  drawCardFromHand,
  ensureSlotStorage,
  getSlotCount,
  getSlotStack,
  getHandSize,
  hasCardInSlot,
  isSlotIdPresent,
  isOwnerForSlot,
  isSlotEmpty,
  mapSlotForClient,
  mapSlotFromClientToServer,
  parseSlotId,
  putCardtoHandFromPile,
  removeCardFromSlot,
  slotIdToString,
};
