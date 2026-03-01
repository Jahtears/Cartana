import { SlotId, SLOT_TYPES } from "../constants/slots.js";
import { refillHandIfEmpty } from "../helpers/pileFlowHelpers.js";
import { slotTopHasAce, slotAnyHasAce } from "../state/cardStore.js";
import {
  hasCardInSlot,
  getSlotStack,
} from "../state/slotStore.js";
import { getSlotValidator } from "./slotValidators.js";
import { debugLog } from "../helpers/debugHelpers.js";
import { deniedTracePayload, technicalDenied, userDenied } from "../helpers/deniedHelpers.js";

function hasWonByEmptyDeckSlot(game, player) {
  if (!player || !game) return false;

  const playerArrayIndex = game.players.indexOf(player);
  if (playerArrayIndex === -1) return false;

  const playerIndex = playerArrayIndex + 1;
  const deckSlot = SlotId.create(playerIndex, SLOT_TYPES.DECK, 1);
  const deckStack = getSlotStack(game, deckSlot);

  return deckStack.length === 0;
}

function hasLoseByEmptyPileSlot(game, player) {
  if (!game) return false;
  if (player && !game.players.includes(player)) return false;

  const pileSlot = SlotId.create(0, SLOT_TYPES.PILE, 1);
  const pileStack = getSlotStack(game, pileSlot);

  return pileStack.length === 0;
}

function ruleCardMustBeInFromSlot(game, player, card, fromSlotId, toSlotId) {
  if (!card || !card.id) {
    return technicalDenied("card_unknown");
  }
  if (!hasCardInSlot(game, fromSlotId, card.id)) {
    // Debug helper: log effective slot state.
    const slotContent = getSlotStack(game, fromSlotId);
    const allSlots = game?.slots instanceof Map
      ? Array.from(game.slots.keys()).map((k) => k.toString())
      : [];
    debugLog("[RULES] DEBUG slotContent", {
      from_slot: fromSlotId,
      requested_card_id: card.id,
      slot_content: slotContent,
      slot_is_empty: !slotContent || (Array.isArray(slotContent) && slotContent.length === 0),
      card_in_game: !!card,
      all_slots: allSlots,
    });
    return technicalDenied("source_slot_missing_card");
  }
  return { valid: true };
}

function ruleFromMustBeClientPlayableSource(game, player, card, fromSlotId, toSlotId) {
  if (
    fromSlotId.type === SLOT_TYPES.HAND
    || fromSlotId.type === SLOT_TYPES.DECK
    || fromSlotId.type === SLOT_TYPES.BENCH
  ) {
    return { valid: true };
  }

  if (fromSlotId.type === SLOT_TYPES.PILE || fromSlotId.type === SLOT_TYPES.TABLE) {
    return technicalDenied("source_shared_forbidden");
  }

  return technicalDenied("invalid_from_slot_type");
}

function ruleFromAndToMustDiffer(game, player, card, fromSlotId, toSlotId) {
  if (String(fromSlotId) === String(toSlotId)) {
    return technicalDenied("same_slot_forbidden");
  }
  return { valid: true };
}

function ruleTopOnlyForDeckAndBenchSource(game, player, card, fromSlotId, toSlotId) {
  if (fromSlotId.type !== SLOT_TYPES.DECK && fromSlotId.type !== SLOT_TYPES.BENCH) {
    return { valid: true };
  }

  const sourceStack = getSlotStack(game, fromSlotId);
  const topCardId = sourceStack.length
    ? sourceStack[sourceStack.length - 1]
    : null;

  if (!topCardId || topCardId !== card.id) {
    return technicalDenied("source_card_not_top");
  }

  return { valid: true };
}

function ruleNotOnOpponentSide(game, player, card, fromSlotId, toSlotId) {
  const fromPlayer = fromSlotId.player;
  const toPlayer = toSlotId.player;
  if (fromPlayer === 0 || toPlayer === 0) {
    return { valid: true };
  }

  // Resolve current player index (1 or 2).
  const playerIndex = (player === game.players[0]) ? 1
    : (player === game.players[1]) ? 2
      : null;
  
  if (playerIndex === null) {
    return technicalDenied("unknown_player");
  }

  // Source slot cannot be opponent-owned.
  if (fromPlayer !== null && fromPlayer !== 0 && fromPlayer !== playerIndex) {
    return userDenied("RULE_OPPONENT_SLOT_FORBIDDEN");
  }

  // Target slot cannot be opponent-owned.
  if (toPlayer !== null && toPlayer !== 0 && toPlayer !== playerIndex) {
    return userDenied("RULE_OPPONENT_SLOT_FORBIDDEN");
  }

  return { valid: true };
}

function ruleDeckMustPlayOnTable(game, player, card, fromSlotId, toSlotId) {
  const fromIsDeck = fromSlotId.type === SLOT_TYPES.DECK;
  const toIsTable = toSlotId.type === SLOT_TYPES.TABLE;

  if (fromIsDeck && !toIsTable) {
    return userDenied("RULE_DECK_TO_TABLE");
  }
  return { valid: true };
}

// Turn system: only current player can play.
function ruleIsPlayersTurn(game, player, card, fromSlotId, toSlotId) {
  if (!game || !game.turn || !game.turn.current) return { valid: true };
  if (game.turn.current !== player) {
    return userDenied("RULE_NOT_YOUR_TURN");
  }
  return { valid: true };
}

function ruleBenchMustPlayOnTable(game, player, card, fromSlotId, toSlotId) {
  // BENCH can only play to TABLE.
  const fromIsBench = fromSlotId.type === SLOT_TYPES.BENCH;
  const toIsTable = toSlotId.type === SLOT_TYPES.TABLE;

  if (fromIsBench && !toIsTable) {
    return userDenied("RULE_BENCH_TO_TABLE");
  }
  return { valid: true };
}

// If an Ace is on top (deck) or in hand, BENCH play is blocked.
function ruleAceMustBePlayed(game, player, card, fromSlotId, toSlotId) {
  if (toSlotId.type !== SLOT_TYPES.BENCH) return { valid: true };

  const playerIndex = game.players.indexOf(player);
  if (playerIndex === -1) {
    return technicalDenied("unknown_player");
  }

  // Convert array index (0/1) to slot player index (1/2).
  const slotPlayerIndex = playerIndex + 1;

  // 1) Ace on top of deck
  const deckSlot = SlotId.create(slotPlayerIndex, SLOT_TYPES.DECK, 1);
  if (slotTopHasAce(game, deckSlot)) {
    return userDenied("RULE_ACE_ON_DECK");
  }

  // 2) Ace anywhere in hand
  const handSlot = SlotId.create(slotPlayerIndex, SLOT_TYPES.HAND, 1);
  if (slotAnyHasAce(game, handSlot)) {
    return userDenied("RULE_ACE_IN_HAND");
  }

  return { valid: true };
}


/* =========================
   SINGLE ENTRY POINT
========================= */

function validateMove(game, player, card, fromSlotId, toSlotId) {
  if (!card) {
    debugLog("[RULES] Carte inconnue", { player, from_slot_id: fromSlotId, to_slot_id: toSlotId });
    return technicalDenied("card_unknown");
  }
  if (!(fromSlotId instanceof SlotId) || !(toSlotId instanceof SlotId)) {
    return technicalDenied("slot_id_not_canonical");
  }

  const globalRules = [
    ruleFromMustBeClientPlayableSource,
    ruleFromAndToMustDiffer,
    ruleCardMustBeInFromSlot,
    ruleTopOnlyForDeckAndBenchSource,
    ruleIsPlayersTurn,
    ruleNotOnOpponentSide,
    ruleDeckMustPlayOnTable,
    ruleBenchMustPlayOnTable,
    ruleAceMustBePlayed,
  ];

  for (const rule of globalRules) {
    const result = rule(game, player, card, fromSlotId, toSlotId);
    if (!result.valid) {
      debugLog("[RULES] RULE_MOVE_DENIED", {
        player,
        card_id: card.id,
        from_slot_id: fromSlotId,
        to_slot_id: toSlotId,
        ...deniedTracePayload(result),
      });
      return result;
    }
  }

  // Slot-specific validation
  const validator = getSlotValidator(toSlotId);

  if (!validator) {
    debugLog("[RULES] WARNING Aucun validateur pour", toSlotId);
    return technicalDenied("slot_validator_missing");
  }

  const slotResult = validator(game, card, fromSlotId, toSlotId);
  if (!slotResult.valid) {
    debugLog("[RULES] MOVE_DENIED_SLOT", {
      player,
      card_id: card.id,
      from_slot_id: fromSlotId,
      to_slot_id: toSlotId,
      ...deniedTracePayload(slotResult),
    });
    return slotResult;
  }

  debugLog("[RULES] RULE_OK", {
    player,
    card_id: card.id,
    from_slot_id: fromSlotId,
    to_slot_id: toSlotId,
  });

  return { valid: true };
}

export {
  validateMove,
  refillHandIfEmpty,
  hasWonByEmptyDeckSlot,
  hasLoseByEmptyPileSlot,
};
