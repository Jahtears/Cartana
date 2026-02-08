//saves.js v1.0
import fs from "fs";
const SAVES_DIR = "././app/saves";
const SAVES_FILE = `${SAVES_DIR}/Saves.json`;

function ensureSavesDir() {
  if (!fs.existsSync(SAVES_DIR)) fs.mkdirSync(SAVES_DIR, { recursive: true });
}

function loadSaves() {
  ensureSavesDir();
  if (!fs.existsSync(SAVES_FILE)) return {};
  try { return JSON.parse(fs.readFileSync(SAVES_FILE, "utf8")); }
  catch { return {}; }
}

function saveSaves(all) {
  ensureSavesDir();
  fs.writeFileSync(SAVES_FILE, JSON.stringify(all, null, 2), "utf8");
}

function saveGameState(game_id, game) {
  const all = loadSaves();
  all[game_id] = { game, savedAt: Date.now() };
  saveSaves(all);
}

function loadGameState(game_id) {
  const all = loadSaves();
    return all[game_id]?.game ?? null;
}

function deleteGameState(game_id) {
  const all = loadSaves();
  delete all[game_id];
  saveSaves(all);
}

export { saveGameState, loadGameState, deleteGameState };