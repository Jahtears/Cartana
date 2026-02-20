// game/slotValidators.js - Slot-specific validators extracted from Regles.js

import { SLOT_TYPES } from "./constants/slots.js";
import {
  getSlotContent,
  isSlotIdPresent,
  parseSlotId,
} from "./helpers/slotHelpers.js";
import { debugLog } from "./helpers/debugHelpers.js";
import { INGAME_MESSAGE } from "./constants/ingameMessages.js";

/**
 * Validate placement on Table slot
 * Rules: empty=[A,R], count=1=[2,R], count=2=[3,R], ... count=9=[10,R], count=10=[D]
 */
export function validateTableSlot(game, card, fromSlotId, toSlotId) {
  if (!isSlotIdPresent(game, toSlotId)) {
    return { valid: false, reason: INGAME_MESSAGE.RULE_TABLE_SLOT_NOT_FOUND };
  }

  const slot = getSlotContent(game, toSlotId);
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
    debugLog("[RULES] MOVE_DENIED_SLOT Table", {
      card_id: card.id,
      to_slot_id: toSlotId,
      count,
      tried: card.value,
      accepted: allowed ?? [],
    });

    return {
      valid: false,
      reason: INGAME_MESSAGE.RULE_CARD_NOT_ALLOWED_ON_TABLE,
      reason_params: { accepted: acceptedStr },
    };
  }

  return { valid: true };
}

/**
 * Validate placement on Deck slot (not allowed)
 */
export function validateDeckSlot(game, card, fromSlotId, toSlotId) {
  return { valid: false, reason: INGAME_MESSAGE.RULE_CANNOT_PLAY_ON_DECK };
}

/**
 * Validate placement on Hand slot (not allowed)
 */
export function validateHandSlot(game, card, fromSlotId, toSlotId) {
  return { valid: false, reason: INGAME_MESSAGE.RULE_CANNOT_PLAY_ON_HAND };
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
  return { valid: false, reason: INGAME_MESSAGE.RULE_CANNOT_PLAY_ON_DRAWPILE };
}

function normalizeSlotType(slotType) {
  const parsed = parseSlotId(slotType);
  if (parsed) return parsed.type;

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
