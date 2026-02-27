// helpers/cardHelpers.js - Card helper utilities

import { DEFAULT_HAND_SIZE } from "../constants/turnFlow.js";
import { getSlotStack } from "./slotHelpers.js";

function getCardById(game, id) {
  if (!game || !id) return null;
  if (game.cardsById && typeof game.cardsById === "object") {
    return game.cardsById[id] ?? null;
  }
  return game.cardIndex?.get?.(id) ?? null;
}

function getTurnValueRank(value) {
  switch (String(value ?? "")) {
    case "A": return 13;
    case "R": return 12;
    case "D": return 11;
    case "V": return 10;
    case "10": return 9;
    case "9": return 8;
    case "8": return 7;
    case "7": return 6;
    case "6": return 5;
    case "5": return 4;
    case "4": return 3;
    case "3": return 2;
    case "2": return 1;
    default: return 0;
  }
}

function compareCardsByTurnValue(c1, c2) {
  return Math.sign(getTurnValueRank(c1?.value) - getTurnValueRank(c2?.value));
}

function slotTopHasAce(game, slotId) {
  const stack = getSlotStack(game, slotId);
  const topId = stack.length ? stack[stack.length - 1] : null;

  if (!topId) return false;

  const card = getCardById(game, topId);
  return !!(card && card.value === "A");
}

function slotAnyHasAce(game, slotId) {
  const ids = getSlotStack(game, slotId);
  for (const id of ids) {
    const card = getCardById(game, id);
    if (card && card.value === "A") return true;
  }
  return false;
}

function findAceCardInHand(game, handSlotId, handSize = DEFAULT_HAND_SIZE) {
  const ids = getSlotStack(game, handSlotId);
  const start = Math.max(0, ids.length - handSize);
  for (let i = ids.length - 1; i >= start; i--) {
    const cardId = ids[i];
    const card = getCardById(game, cardId);
    if (card && card.value === "A") {
      return { slotId: handSlotId, cardId };
    }
  }
  return null;
}

function shuffle(cards) {
  for (let i = cards.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [cards[i], cards[j]] = [cards[j], cards[i]];
  }
}

export {
  compareCardsByTurnValue,
  findAceCardInHand,
  getCardById,
  getTurnValueRank,
  slotAnyHasAce,
  slotTopHasAce,
  shuffle,
};
