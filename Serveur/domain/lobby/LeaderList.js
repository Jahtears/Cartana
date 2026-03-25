import { dbGetLeaderboardObject, dbUpsertLeaderboardEntry } from '../../app/db.js';

function ensurePositiveInt(value) {
  const num = Number(value);
  if (!Number.isFinite(num)) {
    return 0;
  }
  const floored = Math.floor(num);
  return floored > 0 ? floored : 0;
}

function normalizeLeaderboardEntry(stats) {
  const safeStats = stats && typeof stats === 'object' && !Array.isArray(stats) ? stats : {};

  return {
    wins: ensurePositiveInt(safeStats.wins),
    losses: ensurePositiveInt(safeStats.losses),
    draws: ensurePositiveInt(safeStats.draws),
  };
}

function normalizeLeaderboard(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    return {};
  }

  const normalized = {};
  for (const [usernameRaw, stats] of Object.entries(raw)) {
    const username = String(usernameRaw ?? '').trim();
    if (!username) {
      continue;
    }
    if (!isSafeUsername(username)) {
      continue;
    }
    /* eslint-disable security/detect-object-injection */
    normalized[username] = normalizeLeaderboardEntry(stats);
    /* eslint-enable security/detect-object-injection */
  }

  return normalized;
}

function isSafeUsername(u) {
  if (typeof u !== 'string') return false;
  // allow alphanum, dash, underscore, max length 32
  return /^[A-Za-z0-9_-]{1,32}$/.test(u);
}

export function loadLeaderboard() {
  try {
    return normalizeLeaderboard(dbGetLeaderboardObject());
  } catch (err) {
    console.error('[LEADERBOARD] DB error, fallback empty', err);
    return {};
  }
}

export function saveLeaderboard(data) {
  const normalized = normalizeLeaderboard(data);
  for (const [username, stats] of Object.entries(normalized)) {
    const { wins, losses, draws } = stats;
    try {
      if (!isSafeUsername(username)) {
        console.warn('[LEADERBOARD] skipping unsafe username', username);
        continue;
      }

      dbUpsertLeaderboardEntry(username, wins, losses, draws);
    } catch (err) {
      console.warn('[LEADERBOARD] upsert failed for', username, err);
    }
  }
}

function ensurePlayerStats(board, username) {
  if (!isSafeUsername(username)) {
    return { wins: 0, losses: 0, draws: 0 };
  }

  /* eslint-disable security/detect-object-injection */
  if (!board[username]) {
    board[username] = { wins: 0, losses: 0, draws: 0 };
  } else {
    board[username] = normalizeLeaderboardEntry(board[username]);
  }
  const out = board[username];
  /* eslint-enable security/detect-object-injection */
  return out;
}

export function recordLeaderboardResult(players, winner) {
  const normalizedPlayers = Array.isArray(players)
    ? players.map((p) => String(p ?? '').trim()).filter(Boolean)
    : [];

  if (normalizedPlayers.length !== 2 || normalizedPlayers[0] === normalizedPlayers[1]) {
    console.warn('[LEADERBOARD] invalid players payload, skipping update', { players });
    return false;
  }

  const [p1, p2] = normalizedPlayers;
  const board = loadLeaderboard();
  const p1Stats = ensurePlayerStats(board, p1);
  const p2Stats = ensurePlayerStats(board, p2);

  if (winner === null) {
    p1Stats.draws += 1;
    p2Stats.draws += 1;
    saveLeaderboard(board);
    return true;
  }

  const normalizedWinner = String(winner ?? '').trim();
  if (normalizedWinner === p1) {
    p1Stats.wins += 1;
    p2Stats.losses += 1;
    saveLeaderboard(board);
    return true;
  }
  if (normalizedWinner === p2) {
    p2Stats.wins += 1;
    p1Stats.losses += 1;
    saveLeaderboard(board);
    return true;
  }

  console.warn('[LEADERBOARD] invalid winner payload, skipping update', {
    players: normalizedPlayers,
    winner,
  });
  return false;
}

export function getLeaderboardRows() {
  const board = loadLeaderboard();
  const sortedRows = Object.entries(board)
    .map(([username, stats]) => ({ username, ...normalizeLeaderboardEntry(stats) }))
    .sort(
      (a, b) =>
        b.wins - a.wins ||
        b.draws - a.draws ||
        a.losses - b.losses ||
        a.username.localeCompare(b.username),
    );

  let position = 0;
  let currentRank = 0;
  let prevWins = -1;
  let prevDraws = -1;
  let prevLosses = -1;

  return sortedRows.map((row) => {
    position += 1;
    if (
      position === 1 ||
      row.wins !== prevWins ||
      row.draws !== prevDraws ||
      row.losses !== prevLosses
    ) {
      currentRank = position;
    }

    prevWins = row.wins;
    prevDraws = row.draws;
    prevLosses = row.losses;
    return { ...row, rank: currentRank };
  });
}
