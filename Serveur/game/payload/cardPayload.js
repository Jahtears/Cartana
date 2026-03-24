import { SlotId, SLOT_TYPES } from '../constants/slots.js';
import { NEVER_DRAGGABLE_SLOT_TYPES } from '../helpers/slotViewHelpers.js';
import { slotIdToString } from '../state/slotStore.js';

function buildCardPayload(
  card,
  slotId,
  isOwner,
  disableDrag = false,
  slotIdForClient = null,
  forceBack = false,
) {
  const normalizedSlotId = slotIdToString(slotIdForClient ?? slotId);
  const slotType = slotId instanceof SlotId ? slotId.type : null;

  const isFaceDown =
    Boolean(forceBack) ||
    slotType === SLOT_TYPES.PILE ||
    (slotType === SLOT_TYPES.HAND && !isOwner);

  let draggable = Boolean(isOwner);
  if (NEVER_DRAGGABLE_SLOT_TYPES.has(slotType)) {
    draggable = false;
  }
  if (disableDrag) {
    draggable = false;
  }

  return {
    card_id: card.id,
    valeur: isFaceDown ? '' : card.value,
    couleur: isFaceDown ? '' : card.color,
    dos: isFaceDown,
    source: card.source,
    draggable,
    slot_id: normalizedSlotId,
  };
}

export { buildCardPayload };
