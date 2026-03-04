import fs from "fs";
import path from "path";

export let LEADERBOARD_FILE = "./app/saves/Leaderboard.json";

function ensurePositiveInt(value) {
  const num = Number(value);
  if (!Number.isFinite(num)) return 0;
  const floored = Math.floor(num);
  return floored > 0 ? floored : 0;
}

function normalizeLeaderboardEntry(stats) {
  const safeStats = stats && typeof stats === "object" && !Array.isArray(stats)
    ? stats
    : {};

  return {
    wins: ensurePositiveInt(safeStats.wins),
    losses: ensurePositiveInt(safeStats.losses),
    draws: ensurePositiveInt(safeStats.draws),
  };
}

function normalizeLeaderboard(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};

  const normalized = {};
  for (const [usernameRaw, stats] of Object.entries(raw)) {
    const username = String(usernameRaw ?? "").trim();
    if (!username) continue;
    normalized[username] = normalizeLeaderboardEntry(stats);
  }

  return normalized;
}

function ensureLeaderboardDir() {
  const dir = path.dirname(LEADERBOARD_FILE);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

export function setLeaderboardFileForTests(filePath) {
  LEADERBOARD_FILE = filePath;
}

export function loadLeaderboard() {
  ensureLeaderboardDir();
  if (!fs.existsSync(LEADERBOARD_FILE)) {
    fs.writeFileSync(LEADERBOARD_FILE, JSON.stringify({}, null, 2), "utf8");
    return {};
  }

  try {
    const rawContent = fs.readFileSync(LEADERBOARD_FILE, "utf8");
    if (!rawContent.trim()) return {};
    const parsed = JSON.parse(rawContent);
    return normalizeLeaderboard(parsed);
  } catch (err) {
    console.error("[LEADERBOARD] Corrupted Leaderboard.json, fallback empty", err);
    return {};
  }
}

export function saveLeaderboard(data) {
  ensureLeaderboardDir();
  const normalized = normalizeLeaderboard(data);
  fs.writeFileSync(LEADERBOARD_FILE, JSON.stringify(normalized, null, 2), "utf8");
}

function ensurePlayerStats(board, username) {
  if (!board[username]) {
    board[username] = { wins: 0, losses: 0, draws: 0 };
  } else {
    board[username] = normalizeLeaderboardEntry(board[username]);
  }
  return board[username];
}

export function recordLeaderboardResult(players, winner) {
  const normalizedPlayers = Array.isArray(players)
    ? players.map((p) => String(p ?? "").trim()).filter(Boolean)
    : [];

  if (normalizedPlayers.length !== 2 || normalizedPlayers[0] === normalizedPlayers[1]) {
    console.warn("[LEADERBOARD] invalid players payload, skipping update", { players });
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

  const normalizedWinner = String(winner ?? "").trim();
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

  console.warn("[LEADERBOARD] invalid winner payload, skipping update", {
    players: normalizedPlayers,
    winner,
  });
  return false;
}

export function getLeaderboardRows() {
  const board = loadLeaderboard();
  const sortedRows = Object.entries(board)
    .map(([username, stats]) => ({ username, ...normalizeLeaderboardEntry(stats) }))
    .sort((a, b) => (
      b.wins - a.wins
      || b.draws - a.draws
      || a.losses - b.losses
      || a.username.localeCompare(b.username)
    ));

  let position = 0;
  let currentRank = 0;
  let prevWins = -1;
  let prevDraws = -1;
  let prevLosses = -1;

  return sortedRows.map((row) => {
    position += 1;
    if (
      position === 1
      || row.wins !== prevWins
      || row.draws !== prevDraws
      || row.losses !== prevLosses
    ) {
      currentRank = position;
    }

    prevWins = row.wins;
    prevDraws = row.draws;
    prevLosses = row.losses;
    return { ...row, rank: currentRank };
  });
}
