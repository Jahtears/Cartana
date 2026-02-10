// game/Regles.js - Game rules validation (dispatcher only, slot validators delegated)
import {
  makePlayerSlotId,
  getHandSize,
  SLOT_TYPES,
  hasWonByEmptyDeckSlot
} from "./SlotManager.js";
import { refillEmptyHandSlotsFromPile } from "./pileManager.js";
import {
  getSlotContent,
  getPlayerFromSlotId,
  isDeckSlotType,
  isTableSlotType,
  isBenchSlotType,
} from "./SlotHelper.js";
import {
  getSlotValidator,
  _slotTopHasAce,
  _slotAnyHasAce,
} from "./slotValidators.js";

function cardIsInSlot(game, slotId, cardId) {
  if (!game || !game.slots) return false;
  const slotContent = getSlotContent(game, slotId);
  if (!Array.isArray(slotContent)) return slotContent === cardId;
  return slotContent.includes(cardId);
}

function ruleCardMustBeInFromSlot(game, player, card, fromSlotId, toSlotId) {
  if (!card || !card.id) return { valid: false, reason: "Carte inconnue" };
  if (!cardIsInSlot(game, fromSlotId, card.id)) {
    // Debug helper: log effective slot state.
    const slotContent = getSlotContent(game, fromSlotId);
    const allSlots = game?.slots instanceof Map
      ? Array.from(game.slots.keys()).map((k) => k.toString())
      : [];
    console.log("[RULES] DEBUG slotContent", {
      from_slot: fromSlotId,
      requested_card_id: card.id,
      slot_content: slotContent,
      slot_is_empty: !slotContent || (Array.isArray(slotContent) && slotContent.length === 0),
      card_in_game: !!card,
      all_slots: allSlots,
    });
    return { valid: false, reason: "Carte absente du slot source" };
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
    return { valid: false, reason: "Joueur inconnu pour cette partie" };
  }

  // Source slot cannot be opponent-owned.
  if (fromPlayer !== null && fromPlayer !== 0 && fromPlayer !== playerIndex) {
    return { valid: false, reason: "Slot adverse interdit" };
  }

  // Target slot cannot be opponent-owned.
  if (toPlayer !== null && toPlayer !== 0 && toPlayer !== playerIndex) {
    return { valid: false, reason: "Slot adverse interdit" };
  }

  return { valid: true };
}

function ruleDeckMustPlayOnTable(game, player, card, fromSlotId, toSlotId) {
  const fromIsDeck = isDeckSlotType(fromSlotId);
  const toIsTable = isTableSlotType(toSlotId);

  if (fromIsDeck && !toIsTable) {
    return {
      valid: false,
      reason: "Carte du deck → uniquement sur slot Table",
    };
  }
  return { valid: true };
}

// Turn system: only current player can play.
function ruleIsPlayersTurn(game, player, card, fromSlotId, toSlotId) {
  if (!game || !game.turn || !game.turn.current) return { valid: true };
  if (game.turn.current !== player) {
    return { valid: false, reason: "Pas votre tour" };
  }
  return { valid: true };
}

function ruleBenchMustPlayOnTable(game, player, card, fromSlotId, toSlotId) {
  // BENCH can only play to TABLE.
  const fromIsBench = isBenchSlotType(fromSlotId);
  const toIsTable = isTableSlotType(toSlotId);

  if (fromIsBench && !toIsTable) {
    return {
      valid: false,
      reason: "Carte du banc → uniquement sur slot Table",
    };
  }
  return { valid: true };
}

function isBenchSlot(slotId) {
  return isBenchSlotType(slotId);
}

function isHandCompletelyEmpty(game, player) {
  const playerArrayIndex = game.players.indexOf(player);
  if (playerArrayIndex === -1) return false;

  return getHandSize(game, playerArrayIndex + 1) === 0;
}
/**
 * Refill hand from pile when empty.
 * Maximum 5 cards in unique slot 1:HAND:1 or 2:HAND:1.
 * Returns [{ slotId, cardId }, ...].
 */
function refillHandIfEmpty(game, player, handSize = 5) {
  if (!isHandCompletelyEmpty(game, player, handSize)) return [];
  return refillEmptyHandSlotsFromPile(game, player, handSize);
}

// If an Ace is on top (deck) or in hand, BENCH play is blocked.
function ruleAceMustBePlayed(game, player, card, fromSlotId, toSlotId) {
  if (!isBenchSlot(toSlotId)) return { valid: true };

  const playerIndex = game.players.indexOf(player);
  if (playerIndex === -1) {
    return { valid: false, reason: "Joueur inconnu pour cette partie" };
  }

  // Convert array index (0/1) to slot player index (1/2).
  const slotPlayerIndex = playerIndex + 1;

  // 1) Ace on top of deck
  const deckSlot = makePlayerSlotId(slotPlayerIndex, SLOT_TYPES.DECK, 1);
  if (_slotTopHasAce(game, deckSlot)) {
    return {
      valid: false,
      reason: "Banc interdit tant qu'un As est sur le dessus du deck",
    };
  }

  // 2) Ace anywhere in hand
  const handSlot = makePlayerSlotId(slotPlayerIndex, SLOT_TYPES.HAND, 1);
  if (_slotAnyHasAce(game, handSlot)) {
    return {
      valid: false,
      reason: "Banc interdit tant qu'un As est en main",
    };
  }

  return { valid: true };
}


/* =========================
   SINGLE ENTRY POINT
========================= */

function validateMove(game, player, card, fromSlotId, toSlotId) {
  if (!card) {
    console.log("[RULES] Carte inconnue", { player, from_slot_id: fromSlotId, to_slot_id: toSlotId });
    return { valid: false, reason: "Carte inconnue" };
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
      console.log("[RULES] MOVE_DENIED", {
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
    console.log("[RULES] WARNING Aucun validateur pour", toSlotId);
    return { valid: false, reason: "Aucun validateur pour ce slot" };
  }

  const slotResult = validator(game, card, fromSlotId, toSlotId);
  if (!slotResult.valid) {
    console.log("[RULES] MOVE_DENIED_SLOT", {
      player,
      card_id: card.id,
      from_slot_id: fromSlotId,
      to_slot_id: toSlotId,
      reason: slotResult.reason,
    });
    return slotResult;
  }

  console.log("[RULES] MOVE_OK", {
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
};
