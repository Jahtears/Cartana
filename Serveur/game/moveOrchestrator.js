// game/moveOrchestrator.js - Centralized move orchestration
// Coordinates: validate → apply → check win → track updates → prepare response 

import { SLOT_TYPES, SlotId } from "./constants/slots.js";
import { DEFAULT_HAND_SIZE } from "./constants/turnFlow.js";
import { isTableSlot } from "./helpers/slotHelpers.js";
import { GAME_END_REASONS } from "./constants/gameEnd.js";

function technicalDenied(debugReason) {
  return { valid: false, kind: "technical", debug_reason: debugReason };
}

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
 * @param {Object} params.ctx - Request context (for trace)
 * 
 * @returns {Object} Result = { valid, kind?, code?, params?, debug_reason?, response?, winner?, game_end_reason? }
 */
export function orchestrateMove(params) {
  const {
    game_id: gameId,
    game,
    actor,
    card_id: cardId,
    from_slot_id: fromSlotId,
    to_slot_id: toSlotId,
    ctx,
  } = params;
  const {
    validateMove,
    applyMove,
    getCardById,
    isBenchSlot,
    refillHandIfEmpty,
    hasWonByEmptyDeckSlot,
    hasLoseByEmptyPileSlot,
    getTableSlots,
    endTurnAfterBenchPlay,
    withGameUpdate,
  } = ctx;

  //    (player index 0)(slot type pile )(slot index 1)
  const pileSlotId = SlotId.create(0, SLOT_TYPES.PILE, 1);
  const baseResponse = {
    card_id: cardId,
    from_slot_id: fromSlotId,
    to_slot_id: toSlotId,
  };

  // ========================
  // 1) FIND CARD
  // ========================
  const card = getCardById(game, cardId);
  if (!card) {
    return technicalDenied("card_not_found");
  }

  // ========================
  // 2) VALIDATE MOVE
  // ========================
  const validation = validateMove(game, actor, card, fromSlotId, toSlotId);
  if (!validation || validation.valid !== true) {
    if (validation && typeof validation === "object") return validation;
    return technicalDenied("validate_move_denied");
  }

  // ========================
  // 3) APPLY MOVE
  // ========================
  const moveResult = applyMove(game, card, fromSlotId, toSlotId, actor);
  if (!moveResult) {
    return technicalDenied("apply_move_rejected");
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
  const resolveGameEnd = () => {
    if (hasWonByEmptyDeckSlot(game, actor)) {
      return {
        winner: actor,
        game_end_reason: GAME_END_REASONS.DECK_EMPTY,
      };
    }
    if (hasLoseByEmptyPileSlot(game, actor)) {
      return {
        winner: null,
        game_end_reason: GAME_END_REASONS.PILE_EMPTY,
      };
    }
    return null;
  };
  const gameEnd = resolveGameEnd();

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
  if (gameEnd) {
    return {
      valid: true,
      response: { ...baseResponse, winner: gameEnd.winner },
      winner: gameEnd.winner,
      game_end_reason: gameEnd.game_end_reason,
    };
  }

  // ========================
  // 9) IF NOT ENDING TURN, RESPOND IMMEDIATELY
  // ========================
  if (!endsTurn) {
    return {
      valid: true,
      response: baseResponse,
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

  const postTurnGameEnd = resolveGameEnd();
  if (postTurnGameEnd) {
    return {
      valid: true,
      response: { ...baseResponse, winner: postTurnGameEnd.winner },
      winner: postTurnGameEnd.winner,
      game_end_reason: postTurnGameEnd.game_end_reason,
    };
  }

  return {
    valid: true,
    response: baseResponse,
  };
}
