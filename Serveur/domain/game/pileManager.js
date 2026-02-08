// domain/game/pileManager.js - Gestion de la pioche et refill

import { shuffle } from "./state.js";
import {
  makePlayerSlotId,
  makeSharedSlotId,
  getSlotStack,
  drawTop,
  putBottom,
  getTableSlots,
} from "./SlotManager.js";

/**
 * Tirer une carte du haut de la pioche (0:PILE:1)
 * @param {Object} game - État du jeu
 * @returns {Object|null} La carte tirée ou null
 */
export function drawFromPile(game) {
  if (!game?.slots) return null;

  const pileSlot = makeSharedSlotId("P", 1);
  const id = drawTop(game, pileSlot);
  if (!id) return null;

  const card = (game.cardsById && typeof game.cardsById === "object")
    ? (game.cardsById[id] ?? null)
    : null;

  return card;
}
 
/**
 * Remplir les slots de main vides depuis la pioche
 * @param {Object} game - État du jeu
 * @param {Object} player - Le joueur
 * @param {number} maxCards - Nombre max de cartes en main (défaut: 5)
 * @returns {Array} Cartes ajoutées {slot_id, card_id}
 */
export function refillEmptyHandSlotsFromPile(game, player, maxCards = 5) {
  const playerIndex = game.players.indexOf(player);
  if (playerIndex === -1) return [];
  const slotPlayerIndex = playerIndex + 1; // SlotManager: 1/2 pour joueurs, 0 pour shared

  const handSlot = makePlayerSlotId(slotPlayerIndex, "M", 1);
  const handStack = getSlotStack(game, handSlot);

  const given = [];
  const needed = maxCards - handStack.length;

  for (let i = 0; i < needed; i++) {
    const card = drawFromPile(game);
    if (!card) break;

    // Ajoute au TOP de la main (fin du stack)
    handStack.push(card.id);
    given.push({ slot_id: handSlot, card_id: card.id });
  }

  return given;
}

/**
 * Recycler les piles table complètes (12 cartes) sous la pioche
 * - Quand un slot T contient EXACTEMENT 12 cartes
 *   1) shuffle les 12 ids
 *   2) push bot la pioche (fin de game.pioche)
 *   3) vide le slot T
 *
 * @param {Object} game - État du jeu
 * @returns {Object} {recycledSlots, p1Changed}
 */
export function recycleFullTableSlotsToPile(game) {
  const recycledSlots = [];
  if (!game || !game.slots) return { recycledSlots, p1Changed: false };

  const pileSlot = makeSharedSlotId("P", 1);
  const pile = getSlotStack(game, pileSlot);

  // top = dernier index
  const prevTop = pile.length ? pile[pile.length - 1] : null;

  for (const slotId of getTableSlots(game)) {
    const content = getSlotStack(game, slotId);
    if (!Array.isArray(content)) continue;
    if (content.length !== 12) continue;

    const ids = content.slice();
    shuffle(ids);

    // Sous la pioche = bot (index 0)
    for (const id of ids) {
      if (typeof id === "string") putBottom(game, pileSlot, id);
    }

    if (game.slots instanceof Map) {
      game.slots.delete(slotId);
    } else {
      delete game.slots[slotId];
    }
    recycledSlots.push(slotId);

    console.log("[PILE] RECYCLE_TABLE_TO_PILE", {
      slotId,
      count: ids.length,
      pileLength: pile.length,
    });
  }

  const newTop = pile.length ? pile[pile.length - 1] : null;
  const p1Changed = newTop !== prevTop;

  return { recycledSlots, p1Changed };
}
