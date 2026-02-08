// domain/game/slotValidators.js - Slot-specific validators extracted from Regles.js

import { SlotId, SLOT_TYPES, getSlotStack } from "./SlotManager.js";

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

/**
 * Validate placement on Table slot
 * Rules: empty=[A,R], count=1=[2,R], count=2=[3,R], ... count=9=[10,R], count=10=[D]
 */
export function validateTableSlot(game, card, from_slot_id, to_slot_id) {
  const slot = getSlotStack(game, to_slot_id);
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
      to_slot_id,
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
export function validateDeckSlot(game, card, from_slot_id, to_slot_id) {
  return { valid: false, reason: "Impossible de jouer sur un deck" };
}

/**
 * Validate placement on Hand slot (not allowed)
 */
export function validateHandSlot(game, card, from_slot_id, to_slot_id) {
  return { valid: false, reason: "Impossible de jouer sur la main" };
}

/**
 * Validate placement on Bench slot (always allowed)
 */
export function validateBenchSlot(game, card, from_slot_id, to_slot_id) {
  return { valid: true };
}

/**
 * Validate placement on Draw Pile slot (not allowed)
 */
export function validateDrawPileSlot(game, card, from_slot_id, to_slot_id) {
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
export { _getCardById, _isAceValue, _slotTopHasAce, _slotAnyHasAce };
