import {
  NEVER_DRAGGABLE_SLOT_TYPES,
  TOP_ONLY_DRAGGABLE_SLOT_TYPES,
  TOP_ONLY_VISIBLE_SLOT_TYPES,
} from "../constants/slotView.js";

function toSlotStack(slotValue) {
  if (Array.isArray(slotValue)) {
    return slotValue.filter((id) => typeof id === "string" && id.length > 0);
  }
  if (!slotValue) return [];
  return typeof slotValue === "string" ? [slotValue] : [];
}

function getVisibleCardIdsForSlot(slotType, stack) {
  if (!Array.isArray(stack) || stack.length === 0) return [];
  if (TOP_ONLY_VISIBLE_SLOT_TYPES.has(slotType)) {
    return [stack[stack.length - 1]];
  }
  return [...stack];
}

function applySlotDragPolicy(slotType, stack, cardId, isDraggable) {
  if (!isDraggable) return false;
  if (NEVER_DRAGGABLE_SLOT_TYPES.has(slotType)) return false;

  if (TOP_ONLY_DRAGGABLE_SLOT_TYPES.has(slotType)) {
    if (!Array.isArray(stack) || stack.length === 0) return false;
    return cardId === stack[stack.length - 1];
  }

  return true;
}

export {
  applySlotDragPolicy,
  getVisibleCardIdsForSlot,
  toSlotStack,
};
