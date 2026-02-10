// state.js
import crypto from "crypto";

import {
  SlotId,
  SLOT_CONFIG,
  createEmptySlots,
} from "./SlotManager.js";

/* =========================
   DECK GENERATION
========================= */

function createCard(value, color, backColor) {
  return {
    id: crypto.randomUUID(),
    value,
    color,
    backColor,
  };
}

function generateCards(backColor, copies = 1) {
  const values = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "V", "D", "R"];
  const colors = ["coeur", "carreau", "pique", "trefle"];
  const deck = [];

  for (let d = 0; d < copies; d++) {
    for (const v of values) {
      for (const c of colors) {
        deck.push(createCard(v, c, backColor));
      }
    }
  }

  return deck;
}

export function shuffle(deck) {
  for (let i = deck.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
}

/* =========================
   GAME CREATION
========================= */

/**
 * Initial card distribution by slot:
 * - HAND: 5 cards from deckA into 1:HAND:1 / 2:HAND:1
 * - DECK: 26 cards from deckB into 1:DECK:1 / 2:DECK:1
 * - BENCH: 4 empty slots per player
 * - PILE: all remaining deckA cards into 0:PILE:1
 * - TABLE: one empty slot 0:TABLE:1
 */
const INITIAL_DISTRIBUTION = {
  HAND: { player: null, source: "deckA", count: (cfg) => cfg.handSize },
  DECK: { player: null, source: "deckB", count: (cfg) => cfg.personalDeckSize },
  BENCH: { player: null, source: null, count: () => 0 },
  PILE: { player: 0, source: "deckA", count: "ALL" },
  TABLE: { player: 0, source: null, count: () => 0 },
};

function distributeInitialSlots(deckA, deckB, config = {}) {
  const {
    handSize = 5,
    personalDeckSize = 26,
  } = config;

  const ctx = { deckA, deckB, handSize, personalDeckSize };
  const slots = createEmptySlots();
  const allCards = [];

  for (const [slotKey, rule] of Object.entries(INITIAL_DISTRIBUTION)) {
    const cfg = SLOT_CONFIG[slotKey];
    if (!cfg) continue;

    if (rule.player === null) {
      for (let playerIndex = 1; playerIndex <= 2; playerIndex++) {
        for (let i = 1; i <= cfg.count; i++) {
          const slotId = SlotId.create(playerIndex, cfg.type, i);

          let cards = [];
          if (rule.source) {
            const source = ctx[rule.source];
            const n = rule.count === "ALL"
              ? source.length
              : (typeof rule.count === "function" ? rule.count(ctx) : rule.count);
            cards = source.splice(0, n);
          }

          slots.set(slotId, cards.map(c => c.id));
          allCards.push(...cards);
        }
      }
    } else {
      for (let i = 1; i <= cfg.count; i++) {
        const slotId = SlotId.create(rule.player, cfg.type, i);

        let cards = [];
        if (rule.source) {
          const source = ctx[rule.source];
          const n = rule.count === "ALL"
            ? source.length
            : (typeof rule.count === "function" ? rule.count(ctx) : rule.count);
          cards = source.splice(0, n);
        }

        slots.set(slotId, cards.map(c => c.id));
        allCards.push(...cards);
      }
    }
  }

  return { slots, allCards };
}

function initCardsById(game, cards = null) {
  if (!game) return;

  if (!game.cardsById || typeof game.cardsById !== "object") {
    game.cardsById = Object.create(null);
  }

  if (Array.isArray(cards)) {
    for (const card of cards) {
      if (card && typeof card.id === "string") {
        game.cardsById[card.id] = card;
      }
    }
  }
}

export function createGame(player1, player2) {
  // 1) Generate decks
  const deckA = generateCards("rouge");
  const deckB = generateCards("bleu");

  // 2) Shuffle
  shuffle(deckA);
  shuffle(deckB);

  // 3) Build base game object
  const game = {
    players: [player1, player2],
    slots: createEmptySlots(),
    cardsById: Object.create(null),
  };

  // 4) Apply declarative distribution
  const { slots, allCards } = distributeInitialSlots(deckA, deckB, {
    handSize: 5,
    personalDeckSize: 26,
  });

  game.slots = slots;

  // 5) Index cards
  initCardsById(game, allCards);

  console.log("[GAME] CREATE", { player1, player2 });
  return game;
}

/* =========================
   CARD INDEXING
========================= */

export function findCardById(game, id) {
  if (!game || !id) return null;
  if (game.cardsById && typeof game.cardsById === "object") {
    return game.cardsById[id] ?? null;
  }
  return null;
}
