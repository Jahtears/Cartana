// builders/gameBuilder.js - Game and deck builders

import crypto from "crypto";
import { SlotId, SLOT_CONFIG, SLOT_TYPES } from "../constants/slots.js";
import { DEFAULT_HAND_SIZE } from "../constants/turnFlow.js";
import { NEVER_DRAGGABLE_SLOT_TYPES } from "../constants/slotView.js";
import { shuffle } from "../helpers/cardHelpers.js";
import { debugLog } from "../helpers/debugHelpers.js";
import { parseSlotId, slotIdToString } from "../helpers/slotHelpers.js";

const CARD_VALUES = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "V", "D", "R"];
const CARD_COLORS = ["coeur", "carreau", "pique", "trefle"];

const INITIAL_DISTRIBUTION = {
  HAND: { player: null, source: "deckA", count: (cfg) => cfg.handSize },
  DECK: { player: null, source: "deckB", count: (cfg) => cfg.personalDeckSize },
  BENCH: { player: null, source: null, count: () => 0 },
  PILE: { player: 0, source: "deckA", count: "ALL" },
  TABLE: { player: 0, source: null, count: () => 0 },
};

function createEmptySlots() {
  const slots = new Map();

  for (const cfg of Object.values(SLOT_CONFIG)) {
    if (cfg.player === null) {
      for (let p = 1; p <= 2; p++) {
        for (let i = 1; i <= cfg.count; i++) {
          slots.set(SlotId.create(p, cfg.type, i), []);
        }
      }
    } else {
      for (let i = 1; i <= cfg.count; i++) {
        slots.set(SlotId.create(cfg.player, cfg.type, i), []);
      }
    }
  }

  return slots;
}

function createCard(value, color, backColor) {
  return {
    id: crypto.randomUUID(),
    value,
    color,
    backColor,
  };
}

function generateCards(backColor, copies = 1) {
  const deck = [];
  for (let d = 0; d < copies; d++) {
    for (const value of CARD_VALUES) {
      for (const color of CARD_COLORS) {
        deck.push(createCard(value, color, backColor));
      }
    }
  }
  return deck;
}

function createShuffledDecks() {
  const deckA = generateCards("rouge");
  const deckB = generateCards("bleu");
  shuffle(deckA);
  shuffle(deckB);
  return { deckA, deckB };
}

function resolveRuleCardCount(rule, ctx) {
  if (rule.count === "ALL") return ctx[rule.source].length;
  if (typeof rule.count === "function") return rule.count(ctx);
  return rule.count;
}

function takeCardsForRule(rule, ctx) {
  if (!rule.source) return [];
  const source = ctx[rule.source];
  const cardCount = resolveRuleCardCount(rule, ctx);
  return source.splice(0, cardCount);
}

function distributeInitialSlots(slots, deckA, deckB, config = {}) {
  const { handSize = DEFAULT_HAND_SIZE, personalDeckSize = 26 } = config;
  const ctx = { deckA, deckB, handSize, personalDeckSize };

  const allCards = [];

  for (const [slotKey, rule] of Object.entries(INITIAL_DISTRIBUTION)) {
    const cfg = SLOT_CONFIG[slotKey];
    if (!cfg) continue;

    if (rule.player === null) {
      for (let playerIndex = 1; playerIndex <= 2; playerIndex++) {
        for (let i = 1; i <= cfg.count; i++) {
          const slotId = SlotId.create(playerIndex, cfg.type, i);
          const cards = takeCardsForRule(rule, ctx);

          slots.set(slotId, cards.map((card) => card.id));
          allCards.push(...cards);
        }
      }
      continue;
    }

    for (let i = 1; i <= cfg.count; i++) {
      const slotId = SlotId.create(rule.player, cfg.type, i);
      const cards = takeCardsForRule(rule, ctx);

      slots.set(slotId, cards.map((card) => card.id));
      allCards.push(...cards);
    }
  }

  return { slots, allCards };
}

function initCardsById(game, cards = null) {
  if (!game) return;

  if (!game.cardsById || typeof game.cardsById !== "object") {
    game.cardsById = Object.create(null);
  }

  if (!Array.isArray(cards)) return;

  for (const card of cards) {
    if (card && typeof card.id === "string") {
      game.cardsById[card.id] = card;
    }
  }
}

function createBaseGame(player1, player2) {
  return {
    players: [player1, player2],
    slots: new Map(),
    cardsById: Object.create(null),
  };
}

function createGame(player1, player2) {
  // 1) Base game container.
  const game = createBaseGame(player1, player2);

  // 2) Canonical empty slots.
  game.slots = createEmptySlots();

  // 3) Generate and shuffle physical decks.
  const { deckA, deckB } = createShuffledDecks();

  // 4) Deal cards into existing slots.
  const { allCards } = distributeInitialSlots(game.slots, deckA, deckB, {
    handSize: DEFAULT_HAND_SIZE,
    personalDeckSize: 26,
  });

  // 5) Build card lookup index.
  initCardsById(game, allCards);

  debugLog("[GAME] CREATE", { player1, player2 });
  return game;
}

function buildCardData(card, slotId, isOwner, disableDrag = false) {
  const normalizedSlotId = slotIdToString(slotId);
  const parsed = parseSlotId(normalizedSlotId);
  const slotType = parsed?.type ?? null;

  const isFaceDown = slotType === SLOT_TYPES.PILE
    || (slotType === SLOT_TYPES.HAND && !isOwner);

  let draggable = !!isOwner;
  if (NEVER_DRAGGABLE_SLOT_TYPES.has(slotType)) {
    draggable = false;
  }
  if (disableDrag) {
    draggable = false;
  }

  return {
    card_id: card.id,
    valeur: isFaceDown ? "" : card.value,
    couleur: isFaceDown ? "" : card.color,
    dos: isFaceDown,
    dos_couleur: card.backColor,
    draggable,
    slot_id: normalizedSlotId,
  };
}

export {
  createEmptySlots,
  buildCardData,
  createGame,
};
