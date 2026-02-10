// slots.js
import {
  SlotId,
  SLOT_TYPES,
  isPileSlot,
  isTableSlot,
  makePlayerSlotId,
} from "./SlotManager.js";
import { parseSlotIdString, slotIdToString } from "./SlotHelper.js";

/* =========================
   SLOT ID HELPERS (canonical format)
========================= */

function isSlotIdPresent(game, slotId) {
  if (!(game?.slots instanceof Map)) return false;
  return game.slots.has(slotId);
}

/* =========================
   SLOT MAPPING (VIEW)
========================= */

export function mapSlotForClient(slotId, username, game) {
  if (slotId instanceof SlotId) {
    if (slotId.player === 0) {
      return slotIdToString(slotId);
    }

    const userArrayIndex = game.players.indexOf(username); // 0 or 1
    if (userArrayIndex === -1) {
      return slotIdToString(slotId);
    }

    const userPlayerIndex = userArrayIndex + 1; // 1 or 2

    const displayPlayerIndex = slotId.player === userPlayerIndex ? 1 : 2;
    return `${displayPlayerIndex}:${slotId.type}:${slotId.index}`;
  }

  return slotIdToString(slotId);
}

export function isOwnerForSlot(game, slotId, username) {
  const userArrayIndex = game.players.indexOf(username);
  if (userArrayIndex === -1) return false;

  const userPlayerIndex = userArrayIndex + 1;

  if (slotId instanceof SlotId) {
    if (slotId.player === 0) return false;
    return slotId.player === userPlayerIndex;
  }

  const parsed = parseSlotIdString(String(slotId));
  if (!parsed || parsed.playerIndex === 0) return false;
  return parsed.playerIndex === userPlayerIndex;
}

export function mapSlotFromClientToServer(slotId, username, game) {
  if (!slotId || typeof slotId !== "string") return null;

  const parsedClientSlot = parseSlotIdString(slotId);
  if (parsedClientSlot) {
    if (parsedClientSlot.playerIndex === 0) {
      const serverSlot = SlotId.create(0, parsedClientSlot.type, parsedClientSlot.number);
      if (!isPileSlot(serverSlot) && !isTableSlot(serverSlot)) return null;
      return isSlotIdPresent(game, serverSlot) ? serverSlot : null;
    }

    if (parsedClientSlot.playerIndex !== 1 && parsedClientSlot.playerIndex !== 2) return null;

    const userArrayIndex = game.players.indexOf(username);
    if (userArrayIndex === -1) return null;

    const userPlayerIndex = userArrayIndex + 1;

    // Client always sees itself as player index 1.
    let serverPlayerIndex;
    if (parsedClientSlot.playerIndex === 1) {
      serverPlayerIndex = userPlayerIndex;
    } else {
      serverPlayerIndex = userPlayerIndex === 1 ? 2 : 1;
    }

    const serverSlot = makePlayerSlotId(serverPlayerIndex, parsedClientSlot.type, parsedClientSlot.number);
    return isSlotIdPresent(game, serverSlot) ? serverSlot : null;
  }
  return null;
}

/* =========================
   CARD PAYLOAD (VISIBILITY + DRAG)
========================= */
/**
 * Visibility:
 * - HAND: hidden from opponent
 * - PILE: top always hidden
 * - DECK: top always visible
 * - BENCH: always visible
 * - TABLE: top visible
 *
 * Drag:
 * - HAND: draggable by owner
 * - PILE: false
 * - DECK: top draggable by owner
 * - BENCH: bottom draggable by owner
 * - TABLE: false
 */
export function buildCardData(card, slotId, isOwner, disableDrag = false) {
  const normalizedSlotId = slotIdToString(slotId);
  const parsed = parseSlotIdString(normalizedSlotId);
  const slotType = parsed?.type ?? null;

  const isHand = slotType === SLOT_TYPES.HAND;
  const isPile = slotType === SLOT_TYPES.PILE;
  const isDeck = slotType === SLOT_TYPES.DECK;
  const isBench = slotType === SLOT_TYPES.BENCH;
  const isTable = slotType === SLOT_TYPES.TABLE;

  // Visibility
  // - Pile: top hidden
  // - Deck: top visible
  // - Hand: hidden from opponent
  // - Bench/Table: visible
  let dos = false;

  if (isPile) {
    dos = true;
  } else if (isDeck) {
    dos = false;
  } else if (isHand) {
    dos = !isOwner;
  }
  // Bench and Table stay visible.

  // Base draggability
  let draggable = isOwner;

  if (isTable || isPile) {
    draggable = false;
  }

  if (disableDrag) {
    draggable = false;
  }

  return {
    card_id: card.id,
    valeur: dos ? "" : card.value,
    couleur: dos ? "" : card.color,
    dos,
    dos_couleur: card.backColor,
    draggable,
    slot_id: normalizedSlotId,
  };
}

export { slotIdToString };
