// MoveApplier.js v3.2 - Slots = stacks (NO game.stacks)
// Utilise uniquement les primitives SlotManager

import { addTurnBonusTime } from "./turn.js";
import {
  parseSlotId,
  getSlotStack,
  putTop,
  putBottom,
  removeCardFromSlot,
  getTableSlots,
  isSlotEmpty,
  addTableSlot,
  SLOT_TYPES,
} from "./SlotManager.js"; 

/* =========================
   APPLY MOVE (PUBLIC)
========================= */

/**
 * Applique un déplacement validé
 * @returns {{from, to, newTableSlot, deckBecameEmpty}} ou null si refusé
 */
function applyMove(game, card, from_slot_id, to_slot_id, actor) {
  console.log("[APPLY] MOVE_START", {
    card_id: card.id,
    value: card.value,
    color: card.color,
    from: from_slot_id,
    to: to_slot_id,
    actor,
  });

  // Validation minimale des ids de slots (évite de créer des slots fantômes)
  const fromParsed = parseSlotId(from_slot_id);
  const toParsed = parseSlotId(to_slot_id);

  if (!fromParsed || !toParsed) {
    console.warn("[APPLY] MOVE_DENIED_INVALID_SLOT", {
      from_slot_id,
      to_slot_id,
      actor,
      fromParsed: !!fromParsed,
      toParsed: !!toParsed,
    });
    return null;
  }

  // Protection ownership : source non shared (player !== 0) => doit appartenir à actor
  if (!fromParsed.isShared) {
    const actorArrayIndex = game.players.indexOf(actor);  // 0 ou 1
    const actorPlayerIndex = actorArrayIndex + 1;         // 1 ou 2
    
    if (fromParsed.playerIndex !== actorPlayerIndex) {
      console.warn("[APPLY] MOVE_DENIED_NOT_OWNER", {
        actor,
        from_slot_id,
        fromPlayerIndex: fromParsed.playerIndex,
        actorPlayerIndex,
        actorArrayIndex,
      });
      return null;
    }
  }

  // Retire la carte du slot source
  const removed = removeCardFromSlot(game, from_slot_id, card.id);
  if (!removed) {
    console.warn("[APPLY] MOVE_SOURCE_MISSING_CARD", {
      actor,
      from_slot_id,
      card_id: card.id,
    });
    return null;
  }

  let newTableSlot = null;

  // Convention: bot = index 0, top = dernier index
  // - Table/Bench => au TOP (posé dessus / visible)
  // - Autres => au BOT (par défaut, même si souvent interdit par les règles)
  if (toParsed.type === SLOT_TYPES.TABLE || toParsed.type === SLOT_TYPES.BENCH) {
    putTop(game, to_slot_id, card.id);
  } else {
    putBottom(game, to_slot_id, card.id);
  }

  // Assure un slot table vide si besoin
  if (toParsed.type === SLOT_TYPES.TABLE) {
    const tableSlots = getTableSlots(game);
    const last = tableSlots[tableSlots.length - 1] ?? null;
    if (!last || !isSlotEmpty(game, last)) {
      newTableSlot = addTableSlot(game);
    }
  }

  // Deck vide ?
  let deckBecameEmpty = false;
  if (fromParsed.type === SLOT_TYPES.DECK) {
    deckBecameEmpty = getSlotStack(game, from_slot_id).length === 0;
  }

  // Bonus +10s si pose sur table (pas un déplacement T→T)
  if (toParsed.type === SLOT_TYPES.TABLE && fromParsed.type !== SLOT_TYPES.TABLE) {
    if (!game.turn || game.turn.current === actor) {
      addTurnBonusTime(game, 10_000);
    }
  }

  console.log("[APPLY] MOVE_DONE", {
    card_id: card.id,
    from: from_slot_id,
    to: to_slot_id,
    newTableSlot,
    deckBecameEmpty,
  });

  return { from: from_slot_id, to: to_slot_id, newTableSlot, deckBecameEmpty };
}

export { applyMove };