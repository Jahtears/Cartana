// SlotHelper.js - SlotId helpers (canonical format: player:TYPE:index)

import { SLOT_TYPES, SlotId } from "./SlotManager.js";

function parseSlotIdString(str) {
  if (!str || typeof str !== "string") return null;
  const m = str.match(/^(\d+):([A-Z]+):(\d+)$/);
  if (!m) return null;
  const playerIndex = parseInt(m[1], 10);
  const type = m[2];
  const number = parseInt(m[3], 10);
  if (!Number.isFinite(playerIndex) || !Number.isFinite(number)) return null;
  if (!SLOT_TYPES[type]) return null;
  return { playerIndex, type, number };
}

/**
 * Safe access to slot content (canonical Map storage)
 */
function getSlotContent(game, slotId) {
  if (!(game?.slots instanceof Map)) return [];
  return game.slots.get(slotId) || [];
}

function isTableSlotType(slotId) {
  if (slotId instanceof SlotId) return slotId.type === SLOT_TYPES.TABLE;
  const parsed = parseSlotIdString(slotIdToString(slotId));
  if (parsed) return parsed.type === SLOT_TYPES.TABLE;
  return false;
}

function isBenchSlotType(slotId) {
  if (slotId instanceof SlotId) return slotId.type === SLOT_TYPES.BENCH;
  const parsed = parseSlotIdString(slotIdToString(slotId));
  if (parsed) return parsed.type === SLOT_TYPES.BENCH;
  return false;
}

function isDeckSlotType(slotId) {
  if (slotId instanceof SlotId) return slotId.type === SLOT_TYPES.DECK;
  const parsed = parseSlotIdString(slotIdToString(slotId));
  if (parsed) return parsed.type === SLOT_TYPES.DECK;
  return false;
}

/**
 * Extract player index from SlotId or string
 * @returns {number|null}
 */
function getPlayerFromSlotId(slotId) {
  if (slotId instanceof SlotId) {
    if (slotId.player === 0) return 0;
    if (slotId.player === 1 || slotId.player === 2) return slotId.player;
    return null;
  }

  const parsed = parseSlotIdString(slotIdToString(slotId));
  if (parsed) {
    if (parsed.playerIndex === 0) return 0;
    if (parsed.playerIndex === 1 || parsed.playerIndex === 2) return parsed.playerIndex;
    return null;
  }
  return null;
}

/**
 * Normalize slot id to canonical "player:TYPE:index"
 */
function slotIdToString(slotId) {
  if (slotId instanceof SlotId) {
    return slotId.toString();
  }

  if (typeof slotId === "string") {
    const parsed = parseSlotIdString(slotId);
    if (!parsed) return "";
    return `${parsed.playerIndex}:${parsed.type}:${parsed.number}`;
  }

  return "";
}

export {
  parseSlotIdString,
  slotIdToString,
  getSlotContent,
  isTableSlotType,
  isBenchSlotType,
  isDeckSlotType,
  getPlayerFromSlotId,
};
