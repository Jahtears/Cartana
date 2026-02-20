// game/Regles.js - Game rules validation (dispatcher only, slot validators delegated)
import { SlotId, SLOT_TYPES } from "./constants/slots.js";
import { refillHandIfEmpty } from "./helpers/pileFlowHelpers.js";
import {
  slotTopHasAce,
  slotAnyHasAce,
} from "./helpers/cardHelpers.js";
import {
  hasCardInSlot,
  isBenchSlot,
  isDeckSlot,
  getSlotContent,
  getPlayerFromSlotId,
  isTableSlot,
} from "./helpers/slotHelpers.js";
import {
  getSlotValidator,
} from "./slotValidators.js";
import { debugLog } from "./helpers/debugHelpers.js";
import { INGAME_MESSAGE } from "./constants/ingameMessages.js";

function hasWonByEmptyDeckSlot(game, player) {
  if (!player || !game) return false;

  const playerArrayIndex = game.players.indexOf(player);
  if (playerArrayIndex === -1) return false;

  const playerIndex = playerArrayIndex + 1;
  const deckSlot = SlotId.create(playerIndex, SLOT_TYPES.DECK, 1);
  const deckStack = getSlotContent(game, deckSlot);

  return Array.isArray(deckStack) ? deckStack.length === 0 : !deckStack;
}

function haseLoseByEmptyPileSlot(game, player) {
  if (!game) return false;
  if (player && !game.players.includes(player)) return false;

  const pileSlot = SlotId.create(0, SLOT_TYPES.PILE, 1);
  const pileStack = getSlotContent(game, pileSlot);

  return Array.isArray(pileStack) ? pileStack.length === 0 : !pileStack;
}

function ruleCardMustBeInFromSlot(game, player, card, fromSlotId, toSlotId) {
  if (!card || !card.id) return { valid: false, reason: INGAME_MESSAGE.RULE_CARD_UNKNOWN };
  if (!hasCardInSlot(game, fromSlotId, card.id)) {
    // Debug helper: log effective slot state.
    const slotContent = getSlotContent(game, fromSlotId);
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
    return { valid: false, reason: INGAME_MESSAGE.RULE_SOURCE_SLOT_MISSING_CARD };
  }
  return { valid: true };
}

function ruleNotOnOpponentSide(game, player, card, fromSlotId, toSlotId) {
  const fromPlayer = getPlayerFromSlotId(fromSlotId);
  const toPlayer = getPlayerFromSlotId(toSlotId);
  if (fromPlayer === 0 || toPlayer === 0) {
    return { valid: true };
  }

  // Resolve current player index (1 or 2).
  const playerIndex = (player === game.players[0]) ? 1
    : (player === game.players[1]) ? 2
      : null;
  
  if (playerIndex === null) {
    return { valid: false, reason: INGAME_MESSAGE.RULE_UNKNOWN_PLAYER };
  }

  // Source slot cannot be opponent-owned.
  if (fromPlayer !== null && fromPlayer !== 0 && fromPlayer !== playerIndex) {
    return { valid: false, reason: INGAME_MESSAGE.RULE_OPPONENT_SLOT_FORBIDDEN };
  }

  // Target slot cannot be opponent-owned.
  if (toPlayer !== null && toPlayer !== 0 && toPlayer !== playerIndex) {
    return { valid: false, reason: INGAME_MESSAGE.RULE_OPPONENT_SLOT_FORBIDDEN };
  }

  return { valid: true };
}

function ruleDeckMustPlayOnTable(game, player, card, fromSlotId, toSlotId) {
  const fromIsDeck = isDeckSlot(fromSlotId);
  const toIsTable = isTableSlot(toSlotId);

  if (fromIsDeck && !toIsTable) {
    return {
      valid: false,
      reason: INGAME_MESSAGE.RULE_DECK_ONLY_TO_TABLE,
    };
  }
  return { valid: true };
}

// Turn system: only current player can play.
function ruleIsPlayersTurn(game, player, card, fromSlotId, toSlotId) {
  if (!game || !game.turn || !game.turn.current) return { valid: true };
  if (game.turn.current !== player) {
    return { valid: false, reason: INGAME_MESSAGE.RULE_NOT_YOUR_TURN };
  }
  return { valid: true };
}

function ruleBenchMustPlayOnTable(game, player, card, fromSlotId, toSlotId) {
  // BENCH can only play to TABLE.
  const fromIsBench = isBenchSlot(fromSlotId);
  const toIsTable = isTableSlot(toSlotId);

  if (fromIsBench && !toIsTable) {
    return {
      valid: false,
      reason: INGAME_MESSAGE.RULE_BENCH_ONLY_TO_TABLE,
    };
  }
  return { valid: true };
}

// If an Ace is on top (deck) or in hand, BENCH play is blocked.
function ruleAceMustBePlayed(game, player, card, fromSlotId, toSlotId) {
  if (!isBenchSlot(toSlotId)) return { valid: true };

  const playerIndex = game.players.indexOf(player);
  if (playerIndex === -1) {
    return { valid: false, reason: INGAME_MESSAGE.RULE_UNKNOWN_PLAYER };
  }

  // Convert array index (0/1) to slot player index (1/2).
  const slotPlayerIndex = playerIndex + 1;

  // 1) Ace on top of deck
  const deckSlot = SlotId.create(slotPlayerIndex, SLOT_TYPES.DECK, 1);
  if (slotTopHasAce(game, deckSlot)) {
    return {
      valid: false,
      reason: INGAME_MESSAGE.RULE_ACE_BLOCKS_BENCH_DECK_TOP,
    };
  }

  // 2) Ace anywhere in hand
  const handSlot = SlotId.create(slotPlayerIndex, SLOT_TYPES.HAND, 1);
  if (slotAnyHasAce(game, handSlot)) {
    return {
      valid: false,
      reason: INGAME_MESSAGE.RULE_ACE_BLOCKS_BENCH_HAND,
    };
  }

  return { valid: true };
}


/* =========================
   SINGLE ENTRY POINT
========================= */

function validateMove(game, player, card, fromSlotId, toSlotId) {
  if (!card) {
    debugLog("[RULES] Carte inconnue", { player, from_slot_id: fromSlotId, to_slot_id: toSlotId });
    return { valid: false, reason: INGAME_MESSAGE.RULE_CARD_UNKNOWN };
  }

  const globalRules = [
    ruleCardMustBeInFromSlot,
    ruleIsPlayersTurn,
    ruleNotOnOpponentSide,
    ruleDeckMustPlayOnTable,
    ruleBenchMustPlayOnTable,
    ruleAceMustBePlayed,
  ];

  for (const rule of globalRules) {
    const result = rule(game, player, card, fromSlotId, toSlotId);
    if (!result.valid) {
      debugLog("[RULES] MOVE_DENIED", {
        player,
        card_id: card.id,
        from_slot_id: fromSlotId,
        to_slot_id: toSlotId,
        reason: result.reason,
      });
      return result;
    }
  }

  // Slot-specific validation
  const validator = getSlotValidator(toSlotId);

  if (!validator) {
    debugLog("[RULES] WARNING Aucun validateur pour", toSlotId);
    return { valid: false, reason: INGAME_MESSAGE.RULE_SLOT_VALIDATOR_MISSING };
  }

  const slotResult = validator(game, card, fromSlotId, toSlotId);
  if (!slotResult.valid) {
    debugLog("[RULES] MOVE_DENIED_SLOT", {
      player,
      card_id: card.id,
      from_slot_id: fromSlotId,
      to_slot_id: toSlotId,
      reason: slotResult.reason,
    });
    return slotResult;
  }

  debugLog("[RULES] MOVE_OK", {
    player,
    card_id: card.id,
    from_slot_id: fromSlotId,
    to_slot_id: toSlotId,
    reason: slotResult.reason,
  });

  return { valid: true };
}

export {
  validateMove,
  isBenchSlot,
  refillHandIfEmpty,
  hasWonByEmptyDeckSlot,
  haseLoseByEmptyPileSlot,
};
