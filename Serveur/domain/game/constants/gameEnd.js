import { GAME_END_REASONS, GAME_END_REASON_SET } from "../../../shared/constants.js";

function normalizeGameEndReason(reason, fallback = GAME_END_REASONS.ABANDON) {
  const raw = String(reason ?? "").trim().toLowerCase();
  if (!raw) return fallback;

  if (raw === GAME_END_REASONS.ABANDON) return GAME_END_REASONS.ABANDON;
  if (raw === GAME_END_REASONS.DECK_EMPTY) return GAME_END_REASONS.DECK_EMPTY;

  // Legacy aliases
  if (raw === "deck-empty" || raw === "deckempty") return GAME_END_REASONS.DECK_EMPTY;
  if (raw === "forfeit" || raw === "quit" || raw === "leave" || raw === "resign") {
    return GAME_END_REASONS.ABANDON;
  }

  return fallback;
}

export {
  GAME_END_REASONS,
  GAME_END_REASON_SET,
  normalizeGameEndReason,
};
