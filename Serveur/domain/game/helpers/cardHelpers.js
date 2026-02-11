// helpers/cardHelpers.js - Card helper utilities

import { ACE_VALUES, TURN_VALUE_RANK } from "../constants/cards.js";
import { DEFAULT_HAND_SIZE } from "../constants/turnFlow.js";
import { getSlotStack } from "./slotStackHelpers.js";

function getCardById(game, id) {
  if (!game || !id) return null;
  if (game.cardsById && typeof game.cardsById === "object") {
    return game.cardsById[id] ?? null;
  }
  return game.cardIndex?.get?.(id) ?? null;
}

function isAceValue(value) {
  return ACE_VALUES.has(String(value ?? ""));
}

function getTurnValueRank(value) {
  return TURN_VALUE_RANK[String(value)] ?? 0;
}

function compareCardsByTurnValue(c1, c2) {
  const rank1 = c1 ? getTurnValueRank(c1.value) : 0;
  const rank2 = c2 ? getTurnValueRank(c2.value) : 0;
  if (rank1 > rank2) return 1;
  if (rank1 < rank2) return -1;
  return 0;
}

function slotTopHasAce(game, slotId) {
  const stack = getSlotStack(game, slotId);
  const topId = stack.length ? stack[stack.length - 1] : null;

  if (!topId) return false;

  const card = getCardById(game, topId);
  return !!(card && isAceValue(card.value));
}

function slotAnyHasAce(game, slotId) {
  const ids = getSlotStack(game, slotId);
  for (const id of ids) {
    const card = getCardById(game, id);
    if (card && isAceValue(card.value)) return true;
  }
  return false;
}

function findAceCardInHand(game, handSlotId, handSize = DEFAULT_HAND_SIZE) {
  const ids = getSlotStack(game, handSlotId);
  const start = Math.max(0, ids.length - handSize);
  for (let i = ids.length - 1; i >= start; i--) {
    const cardId = ids[i];
    const card = getCardById(game, cardId);
    if (card && isAceValue(card.value)) {
      return { slotId: handSlotId, cardId };
    }
  }
  return null;
}

function shuffle(deck) {
  for (let i = deck.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
}

export {
  compareCardsByTurnValue,
  findAceCardInHand,
  getCardById,
  getTurnValueRank,
  isAceValue,
  slotAnyHasAce,
  slotTopHasAce,
  shuffle,
};
