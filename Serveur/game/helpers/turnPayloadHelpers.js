// helpers/turnPayloadHelpers.js - Canonical turn payload formatting

function buildTurnPayload(turn, { includeEmpty = false, serverNow = Date.now() } = {}) {
  if (!turn) {
    if (!includeEmpty) return null;
    return {
      endsAt: 0,
      durationMs: 0,
      paused: false,
      remainingMs: 0,
      serverNow,
    };
  }

  return {
    current: turn.current,
    turnNumber: turn.number,
    endsAt: turn.endsAt ?? null,
    durationMs: turn.durationMs ?? null,
    paused: !!turn.paused,
    remainingMs: Number(turn.remainingMs ?? 0),
    serverNow,
  };
}

export {
  buildTurnPayload,
};
