// turnClock.js - Pure turn clock operations

const TURN_MS = 15000;

function getRemainingMs(turn, now = Date.now()) {
  if (!turn || typeof turn !== "object") return 0;
  if (turn.paused) {
    return Math.max(0, Number(turn.remainingMs ?? 0));
  }

  const endsAt = Number(turn.endsAt ?? 0);
  if (!Number.isFinite(endsAt) || endsAt <= 0) return 0;
  return Math.max(0, endsAt - now);
}

function startTurnClock(turn, now = Date.now(), durationMs = TURN_MS) {
  if (!turn || typeof turn !== "object") return false;
  const safeDurationMs = Math.max(0, Number(durationMs) || 0);

  turn.durationMs = safeDurationMs;
  turn.endsAt = now + safeDurationMs;
  turn.paused = false;
  turn.remainingMs = 0;
  return true;
}

function pauseTurnClock(turn, now = Date.now()) {
  if (!turn || typeof turn !== "object") return false;
  if (turn.paused) return false;

  const remainingMs = getRemainingMs(turn, now);
  turn.paused = true;
  turn.remainingMs = remainingMs;
  return true;
}

function resumeTurnClock(turn, now = Date.now(), remainingMs = null) {
  if (!turn || typeof turn !== "object") return false;
  if (!turn.paused) return false;

  const safeRemainingMs = Math.max(
    0,
    Number(remainingMs ?? turn.remainingMs ?? 0) || 0
  );
  turn.endsAt = now + safeRemainingMs;
  turn.paused = false;
  turn.remainingMs = 0;
  return true;
}

function addBonusToTurnClock(turn, bonusMs = 0, now = Date.now(), maxRemainingMs = null) {
  if (!turn || typeof turn !== "object") return false;
  if (turn.paused) return false;

  const safeBonusMs = Math.max(0, Number(bonusMs) || 0);
  const remainingMs = getRemainingMs(turn, now);
  const maxMs = Number(
    maxRemainingMs ??
      turn.durationMs ??
      Number.POSITIVE_INFINITY
  );

  const boundedMaxMs = Number.isFinite(maxMs) ? Math.max(0, maxMs) : Number.POSITIVE_INFINITY;
  const nextRemainingMs = Math.min(boundedMaxMs, remainingMs + safeBonusMs);
  turn.endsAt = now + nextRemainingMs;
  turn.paused = false;
  turn.remainingMs = 0;
  return true;
}

function isTurnExpired(turn, now = Date.now()) {
  if (!turn || typeof turn !== "object") return false;
  if (turn.paused) return false;

  const endsAt = Number(turn.endsAt ?? 0);
  if (!Number.isFinite(endsAt) || endsAt <= 0) return false;
  return now >= endsAt;
}

export {
  TURN_MS,
  getRemainingMs,
  startTurnClock,
  pauseTurnClock,
  resumeTurnClock,
  addBonusToTurnClock,
  isTurnExpired,
};
