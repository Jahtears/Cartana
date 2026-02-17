import { SLOT_TYPES } from "../constants/slots.js";
import { SlotId } from "../constants/slots.js";
import { getSlotCount } from "./slotStackHelpers.js";

const SLOT_TYPE_SET = new Set(Object.values(SLOT_TYPES));

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
  return parseSlotId(slotId)?.type === SLOT_TYPES.TABLE;
}

function isPileSlot(slotId) {
  return parseSlotId(slotId)?.type === SLOT_TYPES.PILE;
}

function isBenchSlot(slotId) {
  return parseSlotId(slotId)?.type === SLOT_TYPES.BENCH;
}

function isDeckSlot(slotId) {
  return parseSlotId(slotId)?.type === SLOT_TYPES.DECK;
}

function isHandSlot(slotId) {
  return parseSlotId(slotId)?.type === SLOT_TYPES.HAND;
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
  isTableSlot,
  mapSlotForClient,
  mapSlotFromClientToServer,
  parseSlotId,
  slotIdToString,
};
