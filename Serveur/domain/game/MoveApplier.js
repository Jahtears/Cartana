// MoveApplier.js v3.2 - Slots = stacks (NO game.stacks)
// Uses SlotManager primitives only

import { TURN_MS, addBonusToTurnClock } from "./turnClock.js";
import {
  parseSlotId,
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
 * Apply a validated move.
 * @returns {{from, to, newTableSlot}|null}
 */
function applyMove(game, card, fromSlotId, toSlotId, actor) {
  console.log("[APPLY] MOVE_START", {
    card_id: card.id,
    value: card.value,
    color: card.color,
    from: fromSlotId,
    to: toSlotId,
    actor,
  });

  // Minimal slot-id validation to prevent ghost slots.
  const fromParsed = parseSlotId(fromSlotId);
  const toParsed = parseSlotId(toSlotId);

  if (!fromParsed || !toParsed) {
    console.warn("[APPLY] MOVE_DENIED_INVALID_SLOT", {
      from_slot_id: fromSlotId,
      to_slot_id: toSlotId,
      actor,
      fromParsed: !!fromParsed,
      toParsed: !!toParsed,
    });
    return null;
  }

  // Ownership guard: player slots must belong to actor.
  if (fromParsed.playerIndex !== 0) {
    const actorArrayIndex = game.players.indexOf(actor); // 0 or 1
    const actorPlayerIndex = actorArrayIndex + 1; // 1 or 2
    
    if (fromParsed.playerIndex !== actorPlayerIndex) {
      console.warn("[APPLY] MOVE_DENIED_NOT_OWNER", {
        actor,
        from_slot_id: fromSlotId,
        fromPlayerIndex: fromParsed.playerIndex,
        actorPlayerIndex,
        actorArrayIndex,
      });
      return null;
    }
  }

  // Remove card from source slot.
  const removed = removeCardFromSlot(game, fromSlotId, card.id);
  if (!removed) {
    console.warn("[APPLY] MOVE_SOURCE_MISSING_CARD", {
      actor,
      from_slot_id: fromSlotId,
      card_id: card.id,
    });
    return null;
  }

  let newTableSlot = null;

  // Convention: bottom = index 0, top = last index.
  // - Table/Bench => push on top
  // - Other slots => push at bottom
  if (toParsed.type === SLOT_TYPES.TABLE || toParsed.type === SLOT_TYPES.BENCH) {
    putTop(game, toSlotId, card.id);
  } else {
    putBottom(game, toSlotId, card.id);
  }

  // Ensure there is an empty table slot available.
  if (toParsed.type === SLOT_TYPES.TABLE) {
    const tableSlots = getTableSlots(game);
    const last = tableSlots[tableSlots.length - 1] ?? null;
    if (!last || !isSlotEmpty(game, last)) {
      newTableSlot = addTableSlot(game);
    }
  }

  // +1s bonus on non TABLE->TABLE moves to TABLE (cap at TURN_MS).
  if (toParsed.type === SLOT_TYPES.TABLE && fromParsed.type !== SLOT_TYPES.TABLE) {
    if (game.turn && game.turn.current === actor) {
      addBonusToTurnClock(game.turn, 1000, Date.now(), TURN_MS);
    }
  }

  console.log("[APPLY] MOVE_DONE", {
    card_id: card.id,
    from: fromSlotId,
    to: toSlotId,
    newTableSlot,
  });

  return { from: fromSlotId, to: toSlotId, newTableSlot };
}

export { applyMove };
