//saves.js v1.0
import { SlotId } from '../../game/constants/slots.js';
import { dbGetSave, dbSaveGame, dbDeleteSave } from '../../app/db.js';

function parseSlotIdString(value) {
  if (typeof value !== 'string') {
    return null;
  }
  const match = value.match(/^(\d+):([A-Z]+):(\d+)$/);
  if (!match) {
    return null;
  }

  const player = Number.parseInt(match[1], 10);
  const type = match[2];
  const index = Number.parseInt(match[3], 10);
  if (!Number.isInteger(player) || !Number.isInteger(index)) {
    return null;
  }

  return SlotId.create(player, type, index);
}

function slotIdToString(slotId) {
  if (slotId === null) {
    return '';
  }
  if (typeof slotId === 'string') {
    return slotId;
  }
  if (typeof slotId.toString === 'function') {
    return slotId.toString();
  }
  return String(slotId);
}

function serializeSlots(slots) {
  if (slots instanceof Map) {
    const out = Object.create(null);
    for (const [slotId, stack] of slots.entries()) {
      const key = slotIdToString(slotId);
      out[key] = Array.isArray(stack) ? [...stack] : [];
    }
    return out;
  }

  if (slots && typeof slots === 'object') {
    const out = Object.create(null);
    for (const [rawKey, stack] of Object.entries(slots)) {
      out[String(rawKey)] = Array.isArray(stack) ? [...stack] : [];
    }
    return out;
  }

  return {};
}

function deserializeSlots(rawSlots) {
  const map = new Map();
  if (!rawSlots || typeof rawSlots !== 'object') {
    return map;
  }

  for (const [rawKey, stack] of Object.entries(rawSlots)) {
    const slotId = parseSlotIdString(rawKey);
    if (!slotId) {
      continue;
    }
    map.set(slotId, Array.isArray(stack) ? [...stack] : []);
  }
  return map;
}

function serializeGame(game) {
  if (!game || typeof game !== 'object') {
    return null;
  }
  return {
    ...game,
    slots: serializeSlots(game.slots),
  };
}

function deserializeGame(rawGame) {
  if (!rawGame || typeof rawGame !== 'object') {
    return null;
  }
  const slots = deserializeSlots(rawGame.slots);
  const cardsCount =
    rawGame.cardsById && typeof rawGame.cardsById === 'object'
      ? Object.keys(rawGame.cardsById).length
      : 0;
  if (cardsCount > 0 && slots.size === 0) {
    console.warn('[SAVES] corrupted save ignored: slots empty while cards exist', { cardsCount });
    return null;
  }

  return {
    ...rawGame,
    slots,
  };
}

function saveGameState(game_id, game) {
  const serializableGame = serializeGame(game);
  if (!serializableGame) {
    return;
  }

  try {
    dbSaveGame(game_id, { game: serializableGame });
  } catch (err) {
    console.warn('[SAVES] dbSaveGame failed for', game_id, err);
  }
}

function loadGameState(game_id) {
  try {
    const row = dbGetSave(game_id);
    const rawGame = row?.game ?? null;
    return deserializeGame(rawGame);
  } catch (err) {
    console.warn('[SAVES] dbGetSave failed for', game_id, err);
    return null;
  }
}

function deleteGameState(game_id) {
  try {
    dbDeleteSave(game_id);
  } catch (err) {
    console.warn('[SAVES] dbDeleteSave failed for', game_id, err);
  }
}

export { saveGameState, loadGameState, deleteGameState };
