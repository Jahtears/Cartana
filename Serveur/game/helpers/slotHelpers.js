import { SlotId, SLOT_TYPES } from "../constants/slots.js";

const SLOT_TYPE_SET = new Set(Object.values(SLOT_TYPES));

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

function isValidSlotShape(player, type, index) {
  if (!Number.isInteger(player) || player < 0) return false;
  if (!SLOT_TYPE_SET.has(type)) return false;
  if (!Number.isInteger(index) || index < 1) return false;
  return true;
}

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

function getSlotType(slotId) {
  if (slotId instanceof SlotId) {
    if (!isValidSlotShape(slotId.player, slotId.type, slotId.index)) return null;
    return slotId.type;
  }

  return parseSlotId(slotId)?.type ?? null;
}

function getSlotContent(game, slotId) {
  if (!game?.slots) return [];

  if (game.slots instanceof Map) {
    return game.slots.get(slotId) || [];
  }

  return game.slots[slotId] || [];
}

function getPlayerFromSlotId(slotId) {
  if (slotId instanceof SlotId) {
    if (slotId.player === 0) return 0;
    if (slotId.player === 1 || slotId.player === 2) return slotId.player;
    return null;
  }

  const parsed = parseSlotId(slotId);
  if (parsed) {
    if (parsed.playerIndex === 0) return 0;
    if (parsed.playerIndex === 1 || parsed.playerIndex === 2) return parsed.playerIndex;
    return null;
  }

  return null;
}

function isTableSlot(slotId) {
  return getSlotType(slotId) === SLOT_TYPES.TABLE;
}

function isPileSlot(slotId) {
  return getSlotType(slotId) === SLOT_TYPES.PILE;
}

function isBenchSlot(slotId) {
  return getSlotType(slotId) === SLOT_TYPES.BENCH;
}

function isDeckSlot(slotId) {
  return getSlotType(slotId) === SLOT_TYPES.DECK;
}

function isHandSlot(slotId) {
  return getSlotType(slotId) === SLOT_TYPES.HAND;
}

function getHandSize(game, playerIndex) {
  const handSlot = SlotId.create(playerIndex, SLOT_TYPES.HAND, 1);
  return getSlotCount(game, handSlot);
}

function hasCardInSlot(game, slotId, cardId) {
  if (!game || !game.slots) return false;
  const slotContent = getSlotContent(game, slotId);
  if (!Array.isArray(slotContent)) return slotContent === cardId;
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

  if (slotId instanceof SlotId) {
    if (slotId.player === 0) return false;
    return slotId.player === userPlayerIndex;
  }

  const parsed = parseSlotId(String(slotId));
  if (!parsed || parsed.playerIndex === 0) return false;
  return parsed.playerIndex === userPlayerIndex;
}

function mapSlotFromClientToServer(slotId, username, game) {
  if (!slotId || typeof slotId !== "string") return null;

  const parsedClientSlot = parseSlotId(slotId);
  if (!parsedClientSlot) return null;

  if (parsedClientSlot.playerIndex === 0) {
    const serverSlot = SlotId.create(0, parsedClientSlot.type, parsedClientSlot.number);
    if (!isPileSlot(serverSlot) && !isTableSlot(serverSlot)) return null;
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
  drawTop,
  ensureSlotStorage,
  getSlotCount,
  getSlotStack,
  getSlotType,
  getHandSize,
  hasCardInSlot,
  getSlotContent,
  getPlayerFromSlotId,
  isSlotIdPresent,
  isOwnerForSlot,
  isBenchSlot,
  isDeckSlot,
  isHandSlot,
  isPileSlot,
  isSlotEmpty,
  isTableSlot,
  mapSlotForClient,
  mapSlotFromClientToServer,
  parseSlotId,
  putBottom,
  putTop,
  removeCardFromSlot,
  slotIdToString,
};
