// game/Regles.js - Game rules validation (dispatcher only, slot validators delegated)
import {
  makePlayerSlotId,
  getHandSize,
  isDeckSlot as isDeckSlotId,
  isTableSlot as isTableSlotId,
  isBenchSlot as isBenchSlotId,
  isSharedSlot,
} from "./SlotManager.js";
import { refillEmptyHandSlotsFromPile } from "./pileManager.js";
import { hasWonByEmptyDeckSlot } from "./winConditions.js";
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

function cardIsInSlot(game, slot_id, card_id) {
  if (!game || !game.slots) return false;
  const v = getSlotContent(game, slot_id);
  if (!Array.isArray(v)) return v === card_id;
  return v.includes(card_id);
}

function ruleCardMustBeInFromSlot(game, player, card, from, to) {
  if (!card || !card.id) return { valid: false, reason: "Carte inconnue" };
  if (!cardIsInSlot(game, from, card.id)) {
    // Debug: log what's actually in the slot
    const slotContent = getSlotContent(game, from);
    const allSlots = game?.slots instanceof Map
      ? Array.from(game.slots.keys()).map(k => k.toString?.() ?? String(k))
      : Object.keys(game.slots || {});
    console.log("[RULES] DEBUG slotContent", {
      from_slot: from,
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

function ruleNotOnOpponentSide(game, player, card, from, to) {
  // Les slots shared (player = 0) sont toujours accessibles
  if (isSharedSlot(from) || isSharedSlot(to)) {
    return { valid: true };
  }

  // Déterminer l'index du joueur courant (1 ou 2)
  const playerIndex = (player === game.players[0]) ? 1
    : (player === game.players[1]) ? 2
      : null;
  
  if (playerIndex === null) {
    return { valid: false, reason: "Joueur inconnu pour cette partie" };
  }

  // Vérifier que 'from' n'est pas un slot adverse
  const fromPlayer = getPlayerFromSlotId(from);
  if (fromPlayer !== null && fromPlayer !== 0 && fromPlayer !== playerIndex) {
    return { valid: false, reason: "Slot adverse interdit" };
  }

  // Vérifier que 'to' n'est pas un slot adverse
  const toPlayer = getPlayerFromSlotId(to);
  if (toPlayer !== null && toPlayer !== 0 && toPlayer !== playerIndex) {
    return { valid: false, reason: "Slot adverse interdit" };
  }

  return { valid: true };
}

function ruleDeckMustPlayOnTable(game, player, card, from, to) {
  const fromIsDeck = isDeckSlotId(from) || isDeckSlotType(from);
  const toIsTable = isTableSlotId(to) || isTableSlotType(to);

  if (fromIsDeck && !toIsTable) {
    return {
      valid: false,
      reason: "Carte du deck → uniquement sur slot Table",
    };
  }
  return { valid: true };
}

// Système de tour : seul le joueur courant peut jouer.
function ruleIsPlayersTurn(game, player, card, from, to) {
  if (!game || !game.turn || !game.turn.current) return { valid: true };
  if (game.turn.current !== player) {
    return { valid: false, reason: "Pas votre tour" };
  }
  return { valid: true };
}

function ruleBenchMustPlayOnTable(game, player, card, from, to) {
  // depuis un banc => uniquement sur Table
  const fromIsBench = isBenchSlotId(from) || isBenchSlotType(from);
  const toIsTable = isTableSlotId(to) || isTableSlotType(to);

  if (fromIsBench && !toIsTable) {
    return {
      valid: false,
      reason: "Carte du banc → uniquement sur slot Table",
    };
  }
  return { valid: true };
}

function isBenchSlot(slotId) {
  return isBenchSlotId(slotId) || isBenchSlotType(slotId);
}

function isHandCompletelyEmpty(game, player) {
  const playerArrayIndex = game.players.indexOf(player);
  if (playerArrayIndex === -1) return false;

  return getHandSize(game, playerArrayIndex + 1) === 0;
}
/**
 * Si le slot HAND du joueur est vide, refill immédiatement depuis la pioche.
 * Maximum 5 cartes dans le slot unique 1:HAND:1 ou 2:HAND:1.
 * Retourne la liste des cartes ajoutées: [{slot_id, card_id}, ...]
 */
function refillHandIfEmpty(game, player, handSize = 5) {
  if (!isHandCompletelyEmpty(game, player, handSize)) return [];
  return refillEmptyHandSlotsFromPile(game, player, handSize);
}

// Si as sur top
function ruleAceMustBePlayed(game, player, card, from_slot_id, to_slot_id) {
  if (!isBenchSlot(to_slot_id)) return { valid: true };

  const playerIndex = game.players.indexOf(player);
  if (playerIndex === -1) {
    return { valid: false, reason: "Joueur inconnu pour cette partie" };
  }

  // playerIndex est 0 ou 1, on convertit en 1 ou 2 pour SlotManager
  const slotPlayerIndex = playerIndex + 1;

  // 1) As sur le dessus du deck
  const deckSlot = makePlayerSlotId(slotPlayerIndex, "D", 1);
  if (_slotTopHasAce(game, deckSlot)) {
    return {
      valid: false,
      reason: "Banc interdit tant qu'un As est sur le dessus du deck",
    };
  }

  // 2) As dans la main (n'importe laquelle des cartes)
  const handSlot = makePlayerSlotId(slotPlayerIndex, "M", 1);
  if (_slotAnyHasAce(game, handSlot)) {
    return {
      valid: false,
      reason: "Banc interdit tant qu'un As est en main",
    };
  }

  return { valid: true };
}


/* =========================
   POINT D'ENTRÉE UNIQUE
========================= */

function validateMove(game, player, card, from_slot_id, to_slot_id) {
  if (!card) {
    console.log("[RULES] Carte inconnue", { player, from_slot_id, to_slot_id });
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
    const result = rule(game, player, card, from_slot_id, to_slot_id);
    if (!result.valid) {
      console.log("[RULES] MOVE_DENIED", {
        player,
        card_id: card.id,
        from_slot_id,
        to_slot_id,
        reason: result.reason,
      });
      return result;
    }
  }

  // Validation spécifique du slot
  const validator = getSlotValidator(to_slot_id);

  if (!validator) {
    console.log("[RULES] WARNING Aucun validateur pour", to_slot_id);
    return { valid: false, reason: "Aucun validateur pour ce slot" };
  }

  const slotResult = validator(game, card, from_slot_id, to_slot_id);
  if (!slotResult.valid) {
    console.log("[RULES] MOVE_DENIED_SLOT", {
      player,
      card_id: card.id,
      from_slot_id,
      to_slot_id,
      reason: slotResult.reason,
    });
    return slotResult;
  }

  console.log("[RULES] MOVE_OK", {
    player,
    card_id: card.id,
    from_slot_id,
    to_slot_id,
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
