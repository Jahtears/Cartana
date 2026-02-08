// domain/game/moveOrchestrator.js - Centralized move orchestration
// Coordinates: validate → apply → check win → track updates → prepare response

import { isTableSlot, makeSharedSlotId } from "./SlotManager.js";

/**
 * Orchestra a complete move: validate → apply → refill → track updates → check win
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
 * @param {Function} params.findCardById - Card lookup
 * @param {Function} params.isBenchSlot - Bench detection
 * @param {Function} params.refillHandIfEmpty - Hand refill
 * @param {Function} params.hasWonByEmptyDeckSlot - Win check
 * @param {Function} params.getTableSlots - Get table slots
 * @param {Function} params.endTurnAfterBenchPlay - End turn logic
 * @param {Function} params.withGameUpdate - Game state update builder
 * @param {Function} params.emitSnapshotsToAudience - Broadcast snapshots
 * @param {Object} params.ctx - Request context (for trace)
 * 
 * @returns {Object} Result = { valid, reason?, response?, shouldEnd?, winner? }
 */
export function orchestrateMove(params) {
  const {
    game_id,
    game,
    actor,
    card_id,
    from_slot_id,
    to_slot_id,
    validateMove,
    applyMove,
    findCardById,
    isBenchSlot,
    refillHandIfEmpty,
    hasWonByEmptyDeckSlot,
    getTableSlots,
    endTurnAfterBenchPlay,
    withGameUpdate,
    emitSnapshotsToAudience,
    ctx,
  } = params;

  // Shared slot PILE (player = 0)
  const pileSlotId = makeSharedSlotId("P", 1);

  // ========================
  // 1) FIND CARD
  // ========================
  const card = findCardById(game, card_id);
  if (!card) {
    return {
      valid: false,
      reason: "Carte introuvable",
      code: "NOT_FOUND",
    };
  }

  // ========================
  // 2) VALIDATE MOVE
  // ========================
  const validation = validateMove(game, actor, card, from_slot_id, to_slot_id);
  if (!validation.valid) {
    return {
      valid: false,
      reason: validation.reason,
      code: "MOVE_DENIED",
    };
  }

  // ========================
  // 3) APPLY MOVE
  // ========================
  const moveResult = applyMove(game, card, from_slot_id, to_slot_id, actor);
  if (!moveResult) {
    return {
      valid: false,
      reason: "applyMove rejected",
      code: "MOVE_DENIED", 
    };
  }

  // ========================
  // 4) DETERMINE IF BENCH PLAY (ends turn)
  // ========================
  const endsTurn = isBenchSlot(to_slot_id);

  // ========================
  // 5) REFILL HAND IF NEEDED (only if not ending turn)
  // ========================
  const selfRefill = !endsTurn ? refillHandIfEmpty(game, actor, 5) : [];

  // ========================
  // 6) CHECK WIN CONDITION
  // ========================
  const winner = hasWonByEmptyDeckSlot(game, actor) ? actor : null;

  // ========================
  // 7) TRACK GAME UPDATES (standard move)
  // ========================
  const tableSlots = getTableSlots(game);

  withGameUpdate(game_id, (fx) => {
    if (moveResult.newTableSlot) {
      fx.syncTable(tableSlots);
      fx.touch(moveResult.newTableSlot);
    }
    fx.touch(from_slot_id);
    if (to_slot_id !== moveResult.newTableSlot) fx.touch(to_slot_id);
    for (const refill of selfRefill) fx.touch(refill.slot_id);
    if (selfRefill.length) fx.touch(pileSlotId);
    fx.turn();
  }, ctx?.trace);

  // ========================
  // 8) IF WINNER, STOP HERE
  // ========================
  if (winner) {
    return {
      valid: true,
      response: {
        card_id,
        from_slot_id,
        to_slot_id,
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
        card_id,
        from_slot_id,
        to_slot_id,
      },
    };
  }

  // ========================
  // 10) BENCH PLAY: END TURN
  // ========================
  const { given, recycled } = endTurnAfterBenchPlay(game, actor);

  // Track end-of-turn updates
  const fromExists = game?.slots instanceof Map
    ? game.slots.has(from_slot_id)
    : Object.prototype.hasOwnProperty.call(game.slots || {}, from_slot_id);

  withGameUpdate(game_id, (fx) => {
    if (recycled?.recycledSlots?.length) {
      const freshTableSlots = getTableSlots(game);
      fx.syncTable(freshTableSlots);
    }

    if (!isTableSlot(from_slot_id) || fromExists) fx.touch(from_slot_id);
    fx.touch(to_slot_id);
    for (const refill of given) fx.touch(refill.slot_id);
    fx.touch(pileSlotId);
    fx.turn();
  }, ctx?.trace);

  // Broadcast if pile was recycled
  if (recycled?.recycledSlots?.length && typeof emitSnapshotsToAudience === "function") {
    emitSnapshotsToAudience(game_id, { reason: "recycle" });
  }

  return {
    valid: true,
    response: {
      card_id,
      from_slot_id,
      to_slot_id,
    },
  };
}
