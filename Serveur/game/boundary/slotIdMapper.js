import { SlotId, SLOT_TYPES } from '../constants/slots.js';
import { slotIdToString } from '../state/slotStore.js';

const SLOT_TYPE_SET = new Set(Object.values(SLOT_TYPES));

function isValidSlotShape(player, type, index) {
  if (!Number.isInteger(player) || player < 0) {
    return false;
  }
  if (!SLOT_TYPE_SET.has(type)) {
    return false;
  }
  if (!Number.isInteger(index) || index < 1) {
    return false;
  }
  return true;
}

function parseStringSlotId(value) {
  if (!value) {
    return null;
  }
  const text = String(value);
  const match = text.match(/^(\d+):([A-Z]+):(\d+)$/);
  if (!match) {
    return null;
  }

  const player = parseInt(match[1], 10);
  const type = match[2];
  const index = parseInt(match[3], 10);
  if (!Number.isFinite(player) || !Number.isFinite(index)) {
    return null;
  }

  return { player, type, index };
}

function parseSlotId(slotId) {
  if (slotId instanceof SlotId) {
    if (!isValidSlotShape(slotId.player, slotId.type, slotId.index)) {
      return null;
    }
    return {
      playerIndex: slotId.player,
      type: slotId.type,
      number: slotId.index,
    };
  }

  const parsed = parseStringSlotId(slotId);
  if (!parsed) {
    return null;
  }
  if (!isValidSlotShape(parsed.player, parsed.type, parsed.index)) {
    return null;
  }

  return {
    playerIndex: parsed.player,
    type: parsed.type,
    number: parsed.index,
  };
}

function isSlotIdPresent(game, slotId) {
  if (!(game?.slots instanceof Map)) {
    return false;
  }
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

function mapSlotFromClientToServer(slotId, username, game) {
  if (!slotId || typeof slotId !== 'string') {
    return null;
  }

  const parsedClientSlot = parseSlotId(slotId);
  if (!parsedClientSlot) {
    return null;
  }

  if (parsedClientSlot.playerIndex === 0) {
    const serverSlot = SlotId.create(0, parsedClientSlot.type, parsedClientSlot.number);
    if (parsedClientSlot.type !== SLOT_TYPES.PILE && parsedClientSlot.type !== SLOT_TYPES.TABLE) {
      return null;
    }
    return isSlotIdPresent(game, serverSlot) ? serverSlot : null;
  }

  if (parsedClientSlot.playerIndex !== 1 && parsedClientSlot.playerIndex !== 2) {
    return null;
  }

  const userArrayIndex = game.players.indexOf(username);
  if (userArrayIndex === -1) {
    return null;
  }

  const userPlayerIndex = userArrayIndex + 1;
  const serverPlayerIndex =
    parsedClientSlot.playerIndex === 1 ? userPlayerIndex : userPlayerIndex === 1 ? 2 : 1;

  const serverSlot = SlotId.create(
    serverPlayerIndex,
    parsedClientSlot.type,
    parsedClientSlot.number,
  );
  return isSlotIdPresent(game, serverSlot) ? serverSlot : null;
}

export { isSlotIdPresent, mapSlotForClient, mapSlotFromClientToServer, parseSlotId };
