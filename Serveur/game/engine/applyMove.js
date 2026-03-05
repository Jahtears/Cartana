import { TURN_MS, addBonusToTurnClock } from "../turnClock.js";
import {
  addTableSlot,
} from "../helpers/tableHelper.js";
import {
  getTableSlots,
  getSlotStack,
  removeCardFromSlot,
} from "../state/slotStore.js";
import { SlotId, SLOT_TYPES } from "../constants/slots.js";
import { debugLog, debugWarn } from "../helpers/debugHelpers.js";

/* =========================
   APPLY MOVE (PUBLIC)
========================= */

/**
 * Apply a validated move.
 * @returns {{from, to, createdTableSlotId}|null}
 */
function applyMove(game, card, fromSlotId, toSlotId, actor) {
  debugLog("[APPLY] MOVE_START", {
    card_id: card.id,
    value: card.value,
    color: card.color,
    from: fromSlotId,
    to: toSlotId,
    actor,
  });

  // Internal engine expects canonical SlotId objects at this stage.
  if (!(fromSlotId instanceof SlotId) || !(toSlotId instanceof SlotId)) {
    debugWarn("[APPLY] MOVE_DENIED_INVALID_SLOT", {
      from_slot_id: fromSlotId,
      to_slot_id: toSlotId,
      actor,
      fromIsSlotId: fromSlotId instanceof SlotId,
      toIsSlotId: toSlotId instanceof SlotId,
    });
    return null;
  }

  // Ownership guard: player slots must belong to actor.
  if (fromSlotId.player !== 0) {
    const actorArrayIndex = game.players.indexOf(actor); // 0 or 1
    const actorPlayerIndex = actorArrayIndex + 1; // 1 or 2
    
    if (fromSlotId.player !== actorPlayerIndex) {
      debugWarn("[APPLY] MOVE_DENIED_NOT_OWNER", {
        actor,
        from_slot_id: fromSlotId,
        fromPlayerIndex: fromSlotId.player,
        actorPlayerIndex,
        actorArrayIndex,
      });
      return null;
    }
  }

  // Remove card from source slot.
  const removed = removeCardFromSlot(game, fromSlotId, card.id);
  if (!removed) {
    debugWarn("[APPLY] MOVE_SOURCE_MISSING_CARD", {
      actor,
      from_slot_id: fromSlotId,
      card_id: card.id,
    });
    return null;
  }

  let createdTableSlotId = null;
  let shouldAddTrailingTableSlot = false;

  if (toSlotId.type === SLOT_TYPES.TABLE) {
    const tableSlots = getTableSlots(game);
    const lastTableSlot = tableSlots.length ? tableSlots[tableSlots.length - 1] : null;
    shouldAddTrailingTableSlot = !lastTableSlot || lastTableSlot.index === toSlotId.index;
  }

  // Convention: bottom = index 0, top = last index.
  // - Table/Bench => push on top
  // - Other slots => unshift at bottom
  const targetStack = getSlotStack(game, toSlotId);
  if (toSlotId.type === SLOT_TYPES.TABLE || toSlotId.type === SLOT_TYPES.BENCH) {
    targetStack.push(card.id);
  } else {
    targetStack.unshift(card.id);
  }

  // Keep one trailing table slot only when playing on current last TABLE index.
  if (toSlotId.type === SLOT_TYPES.TABLE && shouldAddTrailingTableSlot) {
    createdTableSlotId = addTableSlot(game);
  }

  // +10s bonus on non TABLE->TABLE moves to TABLE (cap at TURN_MS).
  if (toSlotId.type === SLOT_TYPES.TABLE && fromSlotId.type !== SLOT_TYPES.TABLE) {
    if (game.turn && game.turn.current === actor) {
      addBonusToTurnClock(game.turn, 10000, Date.now(), TURN_MS);
    }
  }

  debugLog("[APPLY] MOVE_DONE", {
    card_id: card.id,
    from: fromSlotId,
    to: toSlotId,
    createdTableSlotId,
  });

  return { from: fromSlotId, to: toSlotId, createdTableSlotId };
}

export { applyMove };
