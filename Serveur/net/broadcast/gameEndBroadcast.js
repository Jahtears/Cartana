export function emitGameEndThenSnapshot(ctx, game_id, result, opts) {
  ctx?.trace?.('GAME_END_ONCE', { game_id, winner: result?.winner ?? null });
  if (typeof ctx.usecases?.session?.emitGameEndOnce === 'function') {
    ctx.usecases.session.emitGameEndOnce(game_id, result, opts);
  } else if (typeof ctx.emitGameEndOnce === 'function') {
    ctx.emitGameEndOnce(game_id, result, opts);
  }

  const snapReason = 'game_end';
  ctx?.trace?.('SNAPSHOT_AUDIENCE', { game_id, reason: snapReason });
  if (typeof ctx.usecases?.session?.emitSnapshotsToAudience === 'function') {
    ctx.usecases.session.emitSnapshotsToAudience(game_id, { reason: snapReason });
  } else if (typeof ctx.emitSnapshotsToAudience === 'function') {
    ctx.emitSnapshotsToAudience(game_id, { reason: snapReason });
  }
}
