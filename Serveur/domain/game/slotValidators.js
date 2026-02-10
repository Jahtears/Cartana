// domain/game/slotValidators.js - Slot-specific validators extracted from Regles.js

import { SlotId, SLOT_TYPES, getSlotStack } from "./SlotManager.js";

const TURN_VALUE_RANK = {
  A: 13,
  R: 12,
  D: 11,
  V: 10,
  "10": 9,
  "9": 8,
  "8": 7,
  "7": 6,
  "6": 5,
  "5": 4,
  "4": 3,
  "3": 2,
  "2": 1,
};

/**
 * Retrieve card from game's card index by ID
 */
function _getCardById(game, id) {
  if (!game || !id) return null;
  return (game.cardsById && typeof game.cardsById === "object")
    ? (game.cardsById[id] ?? null)
    : (game.cardIndex?.get?.(id) ?? null);
}

/**
 * Check if value is an Ace (A or 1)
 */
function _isAceValue(v) {
  const s = String(v ?? "");
  return s === "A" || s === "1";
}

/**
 * Check if the top card of a slot is an Ace
 */
function _slotTopHasAce(game, slotId) {
  const stack = getSlotStack(game, slotId);
  const topId = stack.length ? stack[stack.length - 1] : null;

  if (!topId) return false;

  const c = _getCardById(game, topId);
  return !!(c && _isAceValue(c.value));
}

/**
 * Check if any card in a slot is an Ace
 */
function _slotAnyHasAce(game, slotId) {
  const ids = getSlotStack(game, slotId);
  for (const id of ids) {
    const c = _getCardById(game, id);
    if (c && _isAceValue(c.value)) return true;
  }
  return false;
}

function _valueRank(v) {
  return TURN_VALUE_RANK[String(v)] ?? 0;
}

/**
 * Compare two cards by turn value rank.
 */
function compareCardsByTurnValue(c1, c2) {
  const r1 = c1 ? _valueRank(c1.value) : 0;
  const r2 = c2 ? _valueRank(c2.value) : 0;
  if (r1 > r2) return 1;
  if (r1 < r2) return -1;
  return 0;
}

/**
 * Find an Ace in a hand slot, iterating from top to bottom.
 */
function findAceCardInHand(game, handSlotId, handSize = 5) {
  const ids = getSlotStack(game, handSlotId);
  const start = Math.max(0, ids.length - handSize);
  for (let i = ids.length - 1; i >= start; i--) {
    const cardId = ids[i];
    const card = _getCardById(game, cardId);
    if (card && _isAceValue(card.value)) {
      return { slotId: handSlotId, cardId };
    }
  }
  return null;
}

/**
 * Validate placement on Table slot
 * Rules: empty=[A,R], count=1=[2,R], count=2=[3,R], ... count=9=[10,R], count=10=[D]
 */
export function validateTableSlot(game, card, fromSlotId, toSlotId) {
  const slot = getSlotStack(game, toSlotId);
  const count = slot.length;

  const allowedByCount = [
    ["A", "R"],
    ["2", "R"],
    ["3", "R"],
    ["4", "R"],
    ["5", "R"],
    ["6", "R"],
    ["7", "R"],
    ["8", "R"],
    ["9", "R"],
    ["10", "R"],
    ["V", "R"],
    ["D"],
  ];

  const allowed = allowedByCount[count];

  if (!allowed || !allowed.includes(card.value)) {
    const acceptedStr = allowed ? allowed.join(" ou ") : "aucune";
    console.log("[RULES] MOVE_DENIED_SLOT Table", {
      card_id: card.id,
      to_slot_id: toSlotId,
      count,
      tried: card.value,
      accepted: allowed ?? [],
    });

    return {
      valid: false,
      reason: `Carte non autorisée sur Table (attendu: ${acceptedStr})`,
    };
  }

  return { valid: true };
}

/**
 * Validate placement on Deck slot (not allowed)
 */
export function validateDeckSlot(game, card, fromSlotId, toSlotId) {
  return { valid: false, reason: "Impossible de jouer sur un deck" };
}

/**
 * Validate placement on Hand slot (not allowed)
 */
export function validateHandSlot(game, card, fromSlotId, toSlotId) {
  return { valid: false, reason: "Impossible de jouer sur la main" };
}

/**
 * Validate placement on Bench slot (always allowed)
 */
export function validateBenchSlot(game, card, fromSlotId, toSlotId) {
  return { valid: true };
}

/**
 * Validate placement on Draw Pile slot (not allowed)
 */
export function validateDrawPileSlot(game, card, fromSlotId, toSlotId) {
  return { valid: false, reason: "Impossible de jouer sur la pioche" };
}

function normalizeSlotType(slotType) {
  if (slotType instanceof SlotId) return slotType.type;

  if (typeof slotType === "string") {
    return slotType;
  }

  return null;
}

/**
 * Get appropriate validator for slot type
 * @param {string|SlotId} slotType - Slot type or SlotId
 * @returns {Function|null} Validator function or null
 */
export function getSlotValidator(slotType) {
  const normalized = normalizeSlotType(slotType);
  const validators = {
    [SLOT_TYPES.TABLE]: validateTableSlot,
    [SLOT_TYPES.DECK]: validateDeckSlot,
    [SLOT_TYPES.HAND]: validateHandSlot,
    [SLOT_TYPES.BENCH]: validateBenchSlot,
    [SLOT_TYPES.PILE]: validateDrawPileSlot,
  };
  return validators[normalized] ?? null;
}

/**
 * Export helpers for use in other rules
 */
export {
  _getCardById,
  _isAceValue,
  _slotTopHasAce,
  _slotAnyHasAce,
  compareCardsByTurnValue,
  findAceCardInHand,
};
