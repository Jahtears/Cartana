// constants/slots.js - Canonical slot constants
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

const SLOT_TYPES = {
  DECK: "DECK",
  HAND: "HAND",
  BENCH: "BENCH",
  TABLE: "TABLE",
  PILE: "PILE",
};

const SLOT_TYPE_SET = new Set(Object.values(SLOT_TYPES));

const SLOT_CONFIG = {
  PILE: { player: 0, type: SLOT_TYPES.PILE, count: 1 },
  TABLE: { player: 0, type: SLOT_TYPES.TABLE, count: 1 },
  DECK: { player: null, type: SLOT_TYPES.DECK, count: 1 },
  HAND: { player: null, type: SLOT_TYPES.HAND, count: 1 },
  BENCH: { player: null, type: SLOT_TYPES.BENCH, count: 4 },
};

export { SlotId, SLOT_TYPES, SLOT_TYPE_SET, SLOT_CONFIG };
