// slots.js
import {
  SlotId,
  SLOT_TYPES,
  makePlayerSlotId,
  makeSharedSlotId,
} from "./SlotManager.js";

/* =========================
   SLOT ID HELPERS (new format only)
========================= */

function parseNewSlotId(slot_id) {
  if (!slot_id || typeof slot_id !== "string") return null;

  // New format: "0:TYPE:index" (shared=0, players=1/2)
  const match = slot_id.match(/^(\d+):([A-Z]+):(\d+)$/);
  if (!match) return null;

  const playerIndex = parseInt(match[1], 10);
  const typeRaw = match[2];
  const number = parseInt(match[3], 10);
  if (!Number.isFinite(playerIndex) || !Number.isFinite(number)) return null;

  let type = null;
  if (SLOT_TYPES[typeRaw]) {
    type = typeRaw;
  }

  if (!type) return null;

  return { playerIndex, type, number };
}

function slotIdToNewString(slot_id) {
  if (slot_id instanceof SlotId) {
    return slot_id.toString();
  }

  if (typeof slot_id === "string") {
    const parsedNew = parseNewSlotId(slot_id);
    if (parsedNew) {
      return `${parsedNew.playerIndex}:${parsedNew.type}:${parsedNew.number}`;
    }

    return slot_id;
  }

  return String(slot_id ?? "");
}

function isSlotIdPresent(game, slotId) {
  if (!game?.slots) return false;
  if (game.slots instanceof Map) return game.slots.has(slotId);
  return Object.prototype.hasOwnProperty.call(game.slots, slotId);
}

/* =========================
   SLOT MAPPING (VIEW)
========================= */

export function mapSlotForClient(slot_id, username, game) {
  if (slot_id instanceof SlotId) {
    // Shared slots (player = 0)
    if (slot_id.player === 0) {
      return slotIdToNewString(slot_id);
    }

    // Player slots (player = 1 ou 2)
    const userArrayIndex = game.players.indexOf(username);  // 0 ou 1
    if (userArrayIndex === -1) {
      return slotIdToNewString(slot_id);
    }

    const userPlayerIndex = userArrayIndex + 1;  // 1 ou 2

    // Le client voit toujours son propre joueur comme "1"
    const displayPlayerIndex = slot_id.player === userPlayerIndex ? 1 : 2;
    return `${displayPlayerIndex}:${slot_id.type}:${slot_id.index}`;
  }

  return slotIdToNewString(slot_id);
}

export function isOwnerForSlot(game, slot_id, username) {
  const userArrayIndex = game.players.indexOf(username);
  if (userArrayIndex === -1) return false;

  const userPlayerIndex = userArrayIndex + 1;  // 1 ou 2

  if (slot_id instanceof SlotId) {
    if (slot_id.player === 0) return false;  // Shared
    return slot_id.player === userPlayerIndex;
  }

  const parsed = parseNewSlotId(String(slot_id));
  if (!parsed || parsed.playerIndex === 0) return false;
  return parsed.playerIndex === userPlayerIndex;
}

export function mapSlotFromClientToServer(slot_id, username, game) {
  if (!slot_id || typeof slot_id !== "string") return null;

  const parsedNew = parseNewSlotId(slot_id);
  if (parsedNew) {
    if (parsedNew.playerIndex === 0) {
      const serverSlot = makeSharedSlotId(parsedNew.type, parsedNew.number);
      return isSlotIdPresent(game, serverSlot) ? serverSlot : null;
    }

    if (parsedNew.playerIndex !== 1 && parsedNew.playerIndex !== 2) return null;

    const userArrayIndex = game.players.indexOf(username);
    if (userArrayIndex === -1) return null;

    const userPlayerIndex = userArrayIndex + 1;  // 1 ou 2

    // Le client voit toujours son joueur comme "1"
    let serverPlayerIndex;
    if (parsedNew.playerIndex === 1) {
      serverPlayerIndex = userPlayerIndex;  // Son propre slot
    } else {
      serverPlayerIndex = userPlayerIndex === 1 ? 2 : 1;  // Slot adverse
    }

    const serverSlot = makePlayerSlotId(serverPlayerIndex, parsedNew.type, parsedNew.number);
    return isSlotIdPresent(game, serverSlot) ? serverSlot : null;
  }
  return null;
}

/* =========================
   CARD PAYLOAD (VISIBILITY + DRAG)
========================= */
/**
 * Visibilité:
 * - M (main): toutes cachées à l'adversaire uniquement
 * - P (pile): top toujours caché
 * - D (deck): top toujours révélé
 * - B (banc): toujours révélé, toutes affichées
 * - T (table): toujours révélé, top affiché
 *
 * Drag:
 * - M (main): toutes draggable par owner
 * - P (pile): false
 * - D (deck): top draggable par owner uniquement
 * - B (banc): bot draggable par owner uniquement
 * - T (table): false
 */
export function buildCardData(card, slot_id, isOwner, disableDrag = false) {
  const newSlotId = slotIdToNewString(slot_id);
  const parsedNew = parseNewSlotId(newSlotId);
  const slotType = parsedNew?.type ?? null;

  const isHand = slotType === SLOT_TYPES.HAND;
  const isPile = slotType === SLOT_TYPES.PILE;
  const isDeck = slotType === SLOT_TYPES.DECK;
  const isBench = slotType === SLOT_TYPES.BENCH;
  const isTable = slotType === SLOT_TYPES.TABLE;

  // Visibilité (dos/face)
  // - Pile: top toujours caché
  // - Deck: top toujours révélé
  // - Main: cachée à l'adversaire
  // - Bench/Table: toujours révélé
  let dos = false;

  if (isPile) {
    dos = true; // Pile toujours cachée
  } else if (isDeck) {
    dos = false; // Deck top révélé
  } else if (isHand) {
    dos = !isOwner; // Main cachée à l'adversaire
  }
  // Bench et Table: dos = false (révélé)

  // Draggabilité de base
  let draggable = isOwner;

  if (isTable || isPile) {
    draggable = false; // Table et Pile jamais draggable
  }

  if (disableDrag) {
    draggable = false; // Spectateurs ne peuvent rien drag
  }

  return {
    card_id: card.id,
    valeur: dos ? "" : card.value,
    couleur: dos ? "" : card.color,
    dos,
    dos_couleur: card.backColor,
    draggable,
    slot_id: newSlotId,
  };
}

export { slotIdToNewString };
