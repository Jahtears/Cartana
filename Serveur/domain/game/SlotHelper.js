// SlotHelper.js - Helpers pour SlotId (format 0:TYPE:index)

import { SLOT_TYPES, SlotId } from "./SlotManager.js";

function _parseStringSlotId(str) {
  if (!str) return null;
  const s = String(str);
  const m = s.match(/^(\d+):([A-Z]+):(\d+)$/);
  if (!m) return null;
  const player = parseInt(m[1], 10);
  const type = m[2];
  const index = parseInt(m[3], 10);
  if (!Number.isFinite(player) || !Number.isFinite(index)) return null;
  return { player, type, index };
}

/**
 * Accès sécurisé au contenu d'un slot (fonctionne avec Map ou objet)
 */
function getSlotContent(game, slotId) {
  if (!game?.slots) return [];
  
  // Si c'est une Map
  if (game.slots instanceof Map) {
    return game.slots.get(slotId) || [];
  }
  // Si c'est un objet (rétro-compatibilité)
  return game.slots[slotId] || [];
}

/**
 * Vérification du type de slot
 */
function isNeutralSlot(slotId) {
  if (slotId instanceof SlotId) {
    // Shared = player === 0
    return slotId.player === 0;
  }
  const parsed = _parseStringSlotId(slotId);
  if (parsed) return parsed.player === 0;
  return false;
}

function isTableSlotType(slotId) {
  if (slotId instanceof SlotId) return slotId.type === SLOT_TYPES.TABLE;
  const parsed = _parseStringSlotId(slotId);
  if (parsed) return parsed.type === SLOT_TYPES.TABLE;
  return false;
}

function isPileSlotType(slotId) {
  if (slotId instanceof SlotId) return slotId.type === SLOT_TYPES.PILE;
  const parsed = _parseStringSlotId(slotId);
  if (parsed) return parsed.type === SLOT_TYPES.PILE;
  return false;
}

function isHandSlotType(slotId) {
  if (slotId instanceof SlotId) return slotId.type === SLOT_TYPES.HAND;
  const parsed = _parseStringSlotId(slotId);
  if (parsed) return parsed.type === SLOT_TYPES.HAND;
  return false;
}

function isBenchSlotType(slotId) {
  if (slotId instanceof SlotId) return slotId.type === SLOT_TYPES.BENCH;
  const parsed = _parseStringSlotId(slotId);
  if (parsed) return parsed.type === SLOT_TYPES.BENCH;
  return false;
}

function isDeckSlotType(slotId) {
  if (slotId instanceof SlotId) return slotId.type === SLOT_TYPES.DECK;
  const parsed = _parseStringSlotId(slotId);
  if (parsed) return parsed.type === SLOT_TYPES.DECK;
  return false;
}

/**
 * Extraction du player index à partir d'une SlotId ou string
 * @returns {number|null} - 0 pour shared, 1 ou 2 pour players, null si invalide
 */
function getPlayerFromSlotId(slotId) {
  if (slotId instanceof SlotId) {
    if (slotId.player === 0) return 0;
    if (slotId.player === 1 || slotId.player === 2) return slotId.player;
    return null;
  }

  const parsed = _parseStringSlotId(slotId);
  if (parsed) {
    if (parsed.player === 0) return 0;
    if (parsed.player === 1 || parsed.player === 2) return parsed.player;
    return null;
  }
  return null;
}

/**
 * Conversion SlotId→string et vice versa
 */
function slotIdToString(slotId) {
  if (slotId instanceof SlotId) {
    return slotId.toString();
  }
  return String(slotId);
}

export {
  getSlotContent,
  isNeutralSlot,
  isTableSlotType,
  isPileSlotType,
  isHandSlotType,
  isBenchSlotType,
  isDeckSlotType,
  getPlayerFromSlotId,
  slotIdToString,
};
