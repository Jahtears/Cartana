import { SLOT_TYPES } from '../constants/slots.js';

const TOP_ONLY_VISIBLE_SLOT_TYPES = new Set([SLOT_TYPES.PILE, SLOT_TYPES.DECK, SLOT_TYPES.TABLE]);

const NEVER_DRAGGABLE_SLOT_TYPES = new Set([SLOT_TYPES.PILE, SLOT_TYPES.TABLE]);

const TOP_ONLY_DRAGGABLE_SLOT_TYPES = new Set([SLOT_TYPES.DECK, SLOT_TYPES.BENCH]);

function toSlotStack(slotValue) {
  if (Array.isArray(slotValue)) {
    return slotValue.filter((id) => typeof id === 'string' && id.length > 0);
  }
  if (!slotValue) {
    return [];
  }
  return typeof slotValue === 'string' ? [slotValue] : [];
}

function getVisibleCardIdsForSlot(slotType, stack) {
  if (!Array.isArray(stack) || stack.length === 0) {
    return [];
  }
  if (slotType === SLOT_TYPES.DECK) {
    if (stack.length === 1) {
      return [stack[0]];
    }
    return [stack[stack.length - 2], stack[stack.length - 1]];
  }
  if (TOP_ONLY_VISIBLE_SLOT_TYPES.has(slotType)) {
    return [stack[stack.length - 1]];
  }
  return [...stack];
}

function applySlotDragPolicy(slotType, stack, cardId, isDraggable) {
  if (!isDraggable) {
    return false;
  }
  if (NEVER_DRAGGABLE_SLOT_TYPES.has(slotType)) {
    return false;
  }

  if (TOP_ONLY_DRAGGABLE_SLOT_TYPES.has(slotType)) {
    if (!Array.isArray(stack) || stack.length === 0) {
      return false;
    }
    return cardId === stack[stack.length - 1];
  }

  return true;
}

export {
  applySlotDragPolicy,
  getVisibleCardIdsForSlot,
  NEVER_DRAGGABLE_SLOT_TYPES,
  TOP_ONLY_DRAGGABLE_SLOT_TYPES,
  TOP_ONLY_VISIBLE_SLOT_TYPES,
  toSlotStack,
};
