// SlotManager.js - Canonical slot storage/operations

/* =========================
   SLOT ID CLASS
========================= */

const slotIdCache = new Map();

class SlotId {
  constructor(player, type, index) {
    this.player = player;
    this.type = type;
    this.index = index;
  }

  static create(player, type, index) {
    const key = `${player}|${type}|${index}`;
    if (!slotIdCache.has(key)) {
      slotIdCache.set(key, new SlotId(player, type, index));
    }
    return slotIdCache.get(key);
  }

  toString() {
    return `${this.player}:${this.type}:${this.index}`;
  }
}

/* =========================
   CONSTANTS
========================= */

const SLOT_TYPES = {
  DECK: "DECK",
  HAND: "HAND",
  BENCH: "BENCH",
  TABLE: "TABLE",
  PILE: "PILE",
};
const SLOT_TYPE_SET = new Set(Object.values(SLOT_TYPES));

const SLOT_CONFIG = {
  PILE:  { player: 0, type: SLOT_TYPES.PILE,  count: 1 },
  TABLE: { player: 0, type: SLOT_TYPES.TABLE, count: 1 },
  DECK:  { player: null, type: SLOT_TYPES.DECK,  count: 1 },
  HAND:  { player: null, type: SLOT_TYPES.HAND,  count: 1 },
  BENCH: { player: null, type: SLOT_TYPES.BENCH, count: 4 },
};

/* =========================
   BUILDERS
========================= */

function makePlayerSlotId(playerIndex, slotType, slotNumber) {
  if (!SLOT_TYPE_SET.has(slotType)) {
    throw new TypeError(`Invalid slot type for player slot: ${slotType}`);
  }
  return SlotId.create(playerIndex, slotType, slotNumber);
}

function parseSlotId(slotId) {
  if (!slotId || !(slotId instanceof SlotId)) return null;
  return {
    playerIndex: slotId.player,
    type: slotId.type,
    number: slotId.index,

  };
}

/* =========================
   INIT
========================= */

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

function ensureSlots(game) {
  if (!game.slots) {
    game.slots = createEmptySlots();
  }
}

/* =========================
   CORE API
========================= */

function getSlotStack(game, slotId) {
  ensureSlots(game);
  
  if (!game.slots.has(slotId) && slotId instanceof SlotId && slotId.type === SLOT_TYPES.TABLE) {
    game.slots.set(slotId, []);
  }
  
  return game.slots.get(slotId) || [];
}

function putTop(game, slotId, cardId) {
  if (!cardId) return;
  getSlotStack(game, slotId).push(cardId);
}

function putBottom(game, slotId, cardId) {
  if (!cardId) return;
  getSlotStack(game, slotId).unshift(cardId);
}

function drawTop(game, slotId) {
  const stack = getSlotStack(game, slotId);
  return stack.length ? stack.pop() : null;
}

function removeCardFromSlot(game, slotId, cardId) {
  const stack = getSlotStack(game, slotId);
  const idx = stack.indexOf(cardId);
  if (idx === -1) return false;
  stack.splice(idx, 1);
  return true;
}

function getSlotCount(game, slotId) {
  return getSlotStack(game, slotId).length;
}

function isSlotEmpty(game, slotId) {
  return getSlotCount(game, slotId) === 0;
}


/* =========================
   TABLE API
========================= */

function getTableSlots(game) {
  ensureSlots(game);
  const result = [];
  for (const [slotId] of game.slots) {
    if (slotId instanceof SlotId && slotId.type === SLOT_TYPES.TABLE) {
      result.push(slotId);
    }
  }
  return result.sort((a, b) => a.index - b.index);
}

function addTableSlot(game) {
  const slots = getTableSlots(game);
  const nextIndex = slots.length > 0 ? slots[slots.length - 1].index + 1 : 1;
  const newSlot = SlotId.create(0, SLOT_TYPES.TABLE, nextIndex);
  game.slots.set(newSlot, []);
  return newSlot;
}

function getOrCreateTableSlot(game) {
  const slots = getTableSlots(game);
  const emptySlot = slots.find(id => isSlotEmpty(game, id));
  return emptySlot || addTableSlot(game);
}

function getOrCreateTableSlotWithFlag(game) {
  const before = getTableSlots(game).length;
  const slotId = getOrCreateTableSlot(game);
  const after = getTableSlots(game).length;
  return { slotId, created: after > before };
}

function ensureOneEmptyTableSlot(game) {
  const tableSlots = getTableSlots(game);
  const hasEmpty = tableSlots.some((slotId) => isSlotEmpty(game, slotId));
  if (hasEmpty) return false;
  addTableSlot(game);
  return true;
}

function cleanupEmptyTableSlots(game) {
  const slots = getTableSlots(game);
  const empty = slots.filter(id => isSlotEmpty(game, id));
  
  if (slots.length - empty.length >= slots.length - 1) {
    return [];
  }
  
  const toDelete = empty.slice(1);
  toDelete.forEach(id => game.slots.delete(id));
  return toDelete;
}

/* =========================
   QUERIES
========================= */

function isTableSlot(slotId) {
  return slotId instanceof SlotId && slotId.type === SLOT_TYPES.TABLE;
}

function isPileSlot(slotId) {
  return slotId instanceof SlotId && slotId.type === SLOT_TYPES.PILE;
}

function isBenchSlot(slotId) {
  return slotId instanceof SlotId && slotId.type === SLOT_TYPES.BENCH;
}

function getHandSize(game, playerIndex) {
  return getSlotCount(game, SlotId.create(playerIndex, SLOT_TYPES.HAND, 1));
}

/* =========================
   EXPORTS
========================= */

function hasWonByEmptyDeckSlot(game, player) {
  if (!player || !game) return false;

  const playerArrayIndex = game.players.indexOf(player); // 0 or 1
  if (playerArrayIndex === -1) return false;

  const playerIndex = playerArrayIndex + 1; // 1 or 2 for SlotManager

  // Canonical deck slot: "<player>:DECK:1"
  const deckSlot = makePlayerSlotId(playerIndex, SLOT_TYPES.DECK, 1);

  // Win when deck is empty.
  return getSlotCount(game, deckSlot) === 0;
}

export {
  // Classes & Constants
  SlotId,
  SLOT_TYPES,
  SLOT_CONFIG,

  // Builders
  makePlayerSlotId,
  parseSlotId,

  // Init
  createEmptySlots,

  // Core API
  getSlotStack,
  putTop,
  putBottom,
  drawTop,
  removeCardFromSlot,
  getSlotCount,
  isSlotEmpty,

  // Table API
  getTableSlots,
  addTableSlot,
  getOrCreateTableSlot,
  getOrCreateTableSlotWithFlag,
  ensureOneEmptyTableSlot,
  cleanupEmptyTableSlots,

  // Queries
  isTableSlot,
  isPileSlot,
  isBenchSlot,
  getHandSize,
  hasWonByEmptyDeckSlot,
};
