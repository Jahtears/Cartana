const GAME_END_REASONS = Object.freeze({
  ABANDON: "abandon",
  DECK_EMPTY: "deck_empty",
  PILE_EMPTY: "pile_empty",
});

const GAME_END_REASON_SET = new Set(Object.values(GAME_END_REASONS));

function normalizeGameEndReason(reason, fallback = GAME_END_REASONS.ABANDON) {
  const raw = String(reason ?? "").trim().toLowerCase();
  if (!raw) return fallback;

  if (raw === GAME_END_REASONS.PILE_EMPTY) return GAME_END_REASONS.PILE_EMPTY;
  if (GAME_END_REASON_SET.has(raw)) return raw;

  return fallback;
}

export {
  GAME_END_REASONS,
  GAME_END_REASON_SET,
  normalizeGameEndReason,
};
