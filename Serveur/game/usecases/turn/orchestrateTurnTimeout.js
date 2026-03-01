import { GAME_END_REASONS } from "../../constants/gameEnd.js";
import { MAX_CONSECUTIVE_TIMEOUTS } from "../../constants/turnFlow.js";
import {
  registerTurnTimeoutStreak,
  tryExpireTurn,
} from "../../helpers/turnFlowHelpers.js";

/**
 * Domain orchestration for timeout expiration:
 * - applies turn expiration flow
 * - updates consecutive timeout streaks
 * - computes optional game-end patch
 */
function orchestrateTurnTimeout({ game, now = Date.now() }) {
  const timeout = tryExpireTurn(game, now);
  if (!timeout) return { expired: false };

  const prev = String(timeout.prev ?? "").trim();
  const next = String(timeout.next ?? "").trim();
  const timeoutStreak = prev ? registerTurnTimeoutStreak(game, prev) : 0;
  const reachedTimeoutLimit = !!(next && timeoutStreak >= MAX_CONSECUTIVE_TIMEOUTS);

  return {
    expired: true,
    timeout,
    prev,
    next,
    timeout_streak: timeoutStreak,
    endGamePatch: reachedTimeoutLimit
      ? {
        winner: next,
        reason: GAME_END_REASONS.TIMEOUT_STREAK,
        by: prev,
        at: now,
      }
      : null,
  };
}

export { orchestrateTurnTimeout };
