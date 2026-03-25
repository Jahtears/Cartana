import fs from 'fs';
import path from 'path';
import Database from 'better-sqlite3';

let DB_PATH = process.env.DB_PATH || './app/saves/cartana.db';
let db = null;

/* eslint-disable security/detect-non-literal-fs-filename */
function ensureDbDir() {
  const dir = path.dirname(DB_PATH);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}
/* eslint-enable security/detect-non-literal-fs-filename */

function initDb() {
  if (db) return db;
  ensureDbDir();
  db = new Database(DB_PATH);
  db.exec(`
CREATE TABLE IF NOT EXISTS users (
  user TEXT PRIMARY KEY,
  hash TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS leaderboard (
  username TEXT PRIMARY KEY,
  wins INTEGER DEFAULT 0,
  losses INTEGER DEFAULT 0,
  draws INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS saves (
  game_id TEXT PRIMARY KEY,
  data TEXT,
  savedAt INTEGER
);
`);
  return db;
}

export function setDbPathForTests(p) {
  DB_PATH = p;
  if (db) {
    try {
      db.close();
    } catch (e) {
      console.warn('[DB] close on setDbPathForTests failed', e);
    }
    db = null;
  }
}

export function closeDb() {
  if (db) {
    try {
      db.close();
    } catch (e) {
      console.warn('[DB] close failed', e);
    }
    db = null;
  }
}

// Users
export function dbGetUser(username) {
  const conn = initDb();
  return conn.prepare('SELECT user, hash FROM users WHERE user = ?').get(username) || null;
}

export function dbGetAllUsers() {
  const conn = initDb();
  return conn.prepare('SELECT user, hash FROM users').all();
}

export function dbInsertUser(username, hash) {
  const conn = initDb();
  return conn.prepare('INSERT INTO users(user, hash) VALUES (?, ?)').run(username, hash);
}

// Leaderboard
export function dbGetLeaderboardObject() {
  const conn = initDb();
  const rows = conn.prepare('SELECT username, wins, losses, draws FROM leaderboard').all();
  const out = Object.create(null);
  for (const r of rows) {
    out[r.username] = { wins: r.wins, losses: r.losses, draws: r.draws };
  }
  return out;
}

export function dbUpsertLeaderboardEntry(username, wins, losses, draws) {
  const conn = initDb();
  return conn
    .prepare(
      'INSERT INTO leaderboard(username, wins, losses, draws) VALUES (?, ?, ?, ?) ON CONFLICT(username) DO UPDATE SET wins=excluded.wins, losses=excluded.losses, draws=excluded.draws',
    )
    .run(username, wins, losses, draws);
}

// Saves
export function dbGetSave(game_id) {
  const conn = initDb();
  const row = conn.prepare('SELECT data FROM saves WHERE game_id = ?').get(game_id);
  if (!row) return null;
  try {
    return JSON.parse(row.data);
  } catch {
    return null;
  }
}

export function dbSaveGame(game_id, data) {
  const conn = initDb();
  const str = JSON.stringify(data);
  const savedAt = Date.now();
  return conn
    .prepare(
      'INSERT INTO saves(game_id, data, savedAt) VALUES (?, ?, ?) ON CONFLICT(game_id) DO UPDATE SET data=excluded.data, savedAt=excluded.savedAt',
    )
    .run(game_id, str, savedAt);
}

export function dbDeleteSave(game_id) {
  const conn = initDb();
  return conn.prepare('DELETE FROM saves WHERE game_id = ?').run(game_id);
}

export default function getDb() {
  return initDb();
}
