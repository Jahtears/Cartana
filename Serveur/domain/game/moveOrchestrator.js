// domain/game/moveOrchestrator.js - Centralized move orchestration
// Coordinates: validate → apply → check win → track updates → prepare response 

import { SLOT_TYPES, SlotId } from "./constants/slots.js";
import { DEFAULT_HAND_SIZE } from "./constants/turnFlow.js";
import { isTableSlot } from "./helpers/slotHelpers.js";
import { INLINE_MESSAGE } from "./constants/inlineMessages.js";

export const MOVE_RESULT_CODE = Object.freeze({
  NOT_FOUND: "NOT_FOUND",
  MOVE_DENIED: "MOVE_DENIED",
});

/**
 * Orchestrate a complete move: validate -> apply -> refill -> track updates -> check win.
 * 
 * @param {Object} params - Parameters
 * @param {string} params.game_id - Game ID for state tracking
 * @param {Object} params.game - Game object
 * @param {string} params.actor - Player making the move
 * @param {string} params.card_id - Card ID to move
 * @param {Object} params.from_slot_id - Source slot (server-side SlotId)
 * @param {Object} params.to_slot_id - Target slot (server-side SlotId)
 * @param {Function} params.validateMove - Validation function
 * @param {Function} params.applyMove - Application function
 * @param {Function} params.getCardById - Card lookup
 * @param {Function} params.isBenchSlot - Bench detection
 * @param {Function} params.refillHandIfEmpty - Hand refill
 * @param {Function} params.hasWonByEmptyDeckSlot - Win check
 * @param {Function} params.getTableSlots - Get table slots
 * @param {Function} params.endTurnAfterBenchPlay - End turn logic
 * @param {Function} params.withGameUpdate - Game state update builder
 * @param {Object} params.ctx - Request context (for trace)
 * 
 * @returns {Object} Result = { valid, reason?, response?, shouldEnd?, winner? }
 */
export function orchestrateMove(params) {
  const {
    game_id: gameId,
    game,
    actor,
    card_id: cardId,
    from_slot_id: fromSlotId,
    to_slot_id: toSlotId,
    validateMove,
    applyMove,
    getCardById,
    isBenchSlot,
    refillHandIfEmpty,
    hasWonByEmptyDeckSlot,
    getTableSlots,
    endTurnAfterBenchPlay,
    withGameUpdate,
    ctx,
  } = params;

  //    (player index 0)(slot type pile )(slot index 1)
  const pileSlotId = SlotId.create(0, SLOT_TYPES.PILE, 1);

  // ========================
  // 1) FIND CARD
  // ========================
  const card = getCardById(game, cardId);
  if (!card) {
    return {
      valid: false,
      reason: INLINE_MESSAGE.RULE_CARD_NOT_FOUND,
      code: MOVE_RESULT_CODE.NOT_FOUND,
    };
  }

  // ========================
  // 2) VALIDATE MOVE
  // ========================
  const validation = validateMove(game, actor, card, fromSlotId, toSlotId);
  if (!validation.valid) {
    return {
      valid: false,
      reason: validation.reason,
      reason_params: validation.reason_params ?? {},
      code: MOVE_RESULT_CODE.MOVE_DENIED,
    };
  }

  // ========================
  // 3) APPLY MOVE
  // ========================
  const moveResult = applyMove(game, card, fromSlotId, toSlotId, actor);
  if (!moveResult) {
    return {
      valid: false,
      reason: INLINE_MESSAGE.MOVE_REJECTED,
      code: MOVE_RESULT_CODE.MOVE_DENIED,
    };
  }

  // ========================
  // 4) DETERMINE IF BENCH PLAY (ends turn)
  // ========================
  const endsTurn = isBenchSlot(toSlotId);

  // ========================
  // 5) REFILL HAND IF NEEDED (only if not ending turn)
  // ========================
  const selfRefill = !endsTurn ? refillHandIfEmpty(game, actor, DEFAULT_HAND_SIZE) : [];

  // ========================
  // 6) CHECK WIN CONDITION
  // ========================
  const winner = hasWonByEmptyDeckSlot(game, actor) ? actor : null;

  // ========================
  // 7) TRACK GAME UPDATES (standard move)
  // ========================
  const tableSlots = getTableSlots(game);

  withGameUpdate(gameId, (fx) => {
    if (moveResult.createdTableSlotId) {
      fx.syncTable(tableSlots);
      fx.touch(moveResult.createdTableSlotId);
    }
    fx.touch(fromSlotId);
    if (toSlotId !== moveResult.createdTableSlotId) fx.touch(toSlotId);
    for (const refill of selfRefill) fx.touch(refill.slotId);
    if (selfRefill.length) fx.touch(pileSlotId);
    if (!endsTurn) fx.turn();
  }, ctx?.trace);

  // ========================
  // 8) IF WINNER, STOP HERE
  // ========================
  if (winner) {
    return {
      valid: true,
      response: {
        card_id: cardId,
        from_slot_id: fromSlotId,
        to_slot_id: toSlotId,
        winner,
      },
      winner,
    };
  }

  // ========================
  // 9) IF NOT ENDING TURN, RESPOND IMMEDIATELY
  // ========================
  if (!endsTurn) {
    return {
      valid: true,
      response: {
        card_id: cardId,
        from_slot_id: fromSlotId,
        to_slot_id: toSlotId,
      },
    };
  }

  // ========================
  // 10) BENCH PLAY: END TURN
  // ========================
  const { given, recycled } = endTurnAfterBenchPlay(game, actor);

  // Track end-of-turn updates
  const fromExists = game?.slots instanceof Map && game.slots.has(fromSlotId);

  withGameUpdate(gameId, (fx) => {
    if (recycled?.recycledSlots?.length) {
      const freshTableSlots = getTableSlots(game);
      fx.syncTable(freshTableSlots);
    }

    if (!isTableSlot(fromSlotId) || fromExists) fx.touch(fromSlotId);
    fx.touch(toSlotId);
    for (const refill of given) fx.touch(refill.slotId);
    fx.touch(pileSlotId);
    fx.turn();
  }, ctx?.trace);

  return {
    valid: true,
    response: {
      card_id: cardId,
      from_slot_id: fromSlotId,
      to_slot_id: toSlotId,
    },
  };
}
