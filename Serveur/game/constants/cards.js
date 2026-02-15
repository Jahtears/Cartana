// constants/cards.js - Canonical card constants

const TURN_VALUE_RANK = {
  "A": 13,
  "R": 12,
  "D": 11,
  "V": 10,
  "10": 9,
  "9": 8,
  "8": 7,
  "7": 6,
  "6": 5,
  "5": 4,
  "4": 3,
  "3": 2,
  "2": 1,
};

const ACE_VALUES = new Set(["A", "1"]);

export { ACE_VALUES, TURN_VALUE_RANK };
