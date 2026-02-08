// SlotManager.js v4.4 - ULTRA OPTIMISÉ
// player === 0 pour shared, player === 1 ou 2 pour joueurs

/* =========================
   SLOT ID CLASS
========================= */

const slotIdCache = new Map();

class SlotId {
  constructor(player, type, index) {
    this.player = player;  // 0 = shared, 1 = P1, 2 = P2
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

// 0 = shared, 1+ = player slots
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
  const map = { D: "DECK", M: "HAND", B: "BENCH" };
  const type = map[slotType] || slotType;
  return SlotId.create(playerIndex, type, slotNumber);
}

function makeSharedSlotId(slotType, slotNumber) {
  const map = { T: "TABLE", P: "PILE" };
  const type = map[slotType] || slotType;
  return SlotId.create(0, type, slotNumber);
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
      // Per-player slots (DECK, HAND, BENCH)
      for (let p = 1; p <= 2; p++) {
        for (let i = 1; i <= cfg.count; i++) {
          slots.set(SlotId.create(p, cfg.type, i), []);
        }
      }
    } else {
      // Shared slots (player = 0)
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

function hasCardInSlot(game, slotId, cardId) {
  return getSlotStack(game, slotId).includes(cardId);
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

function peekTop(game, slotId) {
  const stack = getSlotStack(game, slotId);
  return stack.length ? stack[stack.length - 1] : null;
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

function getActiveTableSlotIds(game) {
  return getTableSlots(game).map(id => id.toString());
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

function isHandSlot(slotId) {
  return slotId instanceof SlotId && slotId.type === SLOT_TYPES.HAND;
}

function isBenchSlot(slotId) {
  return slotId instanceof SlotId && slotId.type === SLOT_TYPES.BENCH;
}

function isDeckSlot(slotId) {
  return slotId instanceof SlotId && slotId.type === SLOT_TYPES.DECK;
}

function isSharedSlot(slotId) {
  return slotId instanceof SlotId && slotId.player === 0;
}

function isPlayerSlot(slotId, playerIndex) {
  return slotId instanceof SlotId && slotId.player === playerIndex;
}

function getPlayerSlots(playerIndex, slotType) {
  const cfg = Object.values(SLOT_CONFIG).find(x => x.type === slotType && x.player === null);
  if (!cfg) return [];
  
  const result = [];
  for (let i = 1; i <= cfg.count; i++) {
    result.push(SlotId.create(playerIndex, slotType, i));
  }
  return result;
}

function getHandSize(game, playerIndex) {
  return getSlotCount(game, SlotId.create(playerIndex, SLOT_TYPES.HAND, 1));
}

/* =========================
   EXPORTS
========================= */

export {
  // Classes & Constants
  SlotId,
  SLOT_TYPES,
  SLOT_CONFIG,

  // Builders
  makePlayerSlotId,
  makeSharedSlotId,
  parseSlotId,

  // Init
  createEmptySlots,

  // Core API
  getSlotStack,
  putTop,
  putBottom,
  drawTop,
  hasCardInSlot,
  removeCardFromSlot,
  getSlotCount,
  isSlotEmpty,
  peekTop,

  // Table API
  getTableSlots,
  addTableSlot,
  getOrCreateTableSlot,
  cleanupEmptyTableSlots,
  getActiveTableSlotIds,

  // Queries
  isTableSlot,
  isPileSlot,
  isHandSlot,
  isBenchSlot,
  isDeckSlot,
  isSharedSlot,
  isPlayerSlot,
  getPlayerSlots,
  getHandSize,
};
