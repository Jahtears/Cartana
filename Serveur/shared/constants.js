// shared/constants.js

export const GAME_MESSAGE = {
  TURN_START: "TURN_START",
  MOVE_OK: "MOVE_OK",
  MOVE_DENIED: "MOVE_DENIED",
  INFO: "INFO",
  WARN: "WARN",
  ERROR: "ERROR",
};

export const UI_EVENT = {
  GAME_MESSAGE: "show_game_message",
};

export const GAME_END_REASONS = {
  ABANDON: "abandon",
  DECK_EMPTY: "deck_empty",
};

export const GAME_END_REASON_SET = new Set(Object.values(GAME_END_REASONS));
