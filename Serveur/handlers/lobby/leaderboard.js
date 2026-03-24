import { getLeaderboardRows } from '../../domain/lobby/LeaderList.js';

export function handleGetLeaderboard(ctx, ws, req) {
  const leaderboard = getLeaderboardRows();
  ctx.sendRes(ws, req, true, { leaderboard });
  return true;
}
