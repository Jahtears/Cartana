import { SlotId, SLOT_TYPES } from "../constants/slots.js";
import { getSlotStack } from "../state/slotStore.js";
import { debugLog } from "../helpers/debugHelpers.js";
import { technicalDenied, userDenied } from "../helpers/deniedHelpers.js";

/**
 * Validate placement on Table slot
 * Rules: empty=[A,R], count=1=[2,R], count=2=[3,R], ... count=9=[10,R], count=10=[D]
 */
export function validateTableSlot(game, card, fromSlotId, toSlotId) {
  if (!(toSlotId instanceof SlotId)) {
    return technicalDenied("slot_id_not_canonical");
  }

  if (!(game?.slots instanceof Map) || !game.slots.has(toSlotId)) {
    return technicalDenied("table_slot_not_found");
  }

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
    debugLog("[RULES] MOVE_DENIED_SLOT Table", {
      card_id: card.id,
      to_slot_id: toSlotId,
      count,
      tried: card.value,
      accepted: allowed ?? [],
    });

    return {
      valid: false,
      kind: "user",
      code: "RULE_ALLOWED_ON_TABLE",
      params: { accepted: acceptedStr },
    };
  }

  return { valid: true };
}

/**
 * Validate placement on Deck slot (not allowed)
 */
function staticDeny(code) {
  return () => userDenied(code);
}

export const validateDeckSlot = staticDeny("RULE_MOVE_DENIED");

/**
 * Validate placement on Hand slot (not allowed)
 */
export const validateHandSlot = staticDeny("RULE_MOVE_DENIED");

/**
 * Validate placement on Bench slot (always allowed)
 */
export function validateBenchSlot(game, card, fromSlotId, toSlotId) {
  return { valid: true };
}

/**
 * Validate placement on Draw Pile slot (not allowed)
 */
export const validateDrawPileSlot = staticDeny("RULE_MOVE_DENIED");

/**
 * Get appropriate validator for slot type
 * @param {SlotId} slotId - Canonical SlotId
 * @returns {Function|null} Validator function or null
 */
export function getSlotValidator(slotId) {
  if (!(slotId instanceof SlotId)) return null;

  const validators = {
    [SLOT_TYPES.TABLE]: validateTableSlot,
    [SLOT_TYPES.DECK]: validateDeckSlot,
    [SLOT_TYPES.HAND]: validateHandSlot,
    [SLOT_TYPES.BENCH]: validateBenchSlot,
    [SLOT_TYPES.PILE]: validateDrawPileSlot,
  };
  return validators[slotId.type] ?? null;
}
