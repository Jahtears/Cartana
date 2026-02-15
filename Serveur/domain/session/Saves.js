//saves.js v1.0
import fs from "fs";
import { SlotId } from "../../game/constants/slots.js";
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

function parseSlotIdString(value) {
  if (typeof value !== "string") return null;
  const match = value.match(/^(\d+):([A-Z]+):(\d+)$/);
  if (!match) return null;

  const player = Number.parseInt(match[1], 10);
  const type = match[2];
  const index = Number.parseInt(match[3], 10);
  if (!Number.isInteger(player) || !Number.isInteger(index)) return null;

  return SlotId.create(player, type, index);
}

function slotIdToString(slotId) {
  if (slotId == null) return "";
  if (typeof slotId === "string") return slotId;
  if (typeof slotId.toString === "function") return slotId.toString();
  return String(slotId);
}

function serializeSlots(slots) {
  if (slots instanceof Map) {
    const out = Object.create(null);
    for (const [slotId, stack] of slots.entries()) {
      const key = slotIdToString(slotId);
      out[key] = Array.isArray(stack) ? [...stack] : [];
    }
    return out;
  }

  if (slots && typeof slots === "object") {
    const out = Object.create(null);
    for (const [rawKey, stack] of Object.entries(slots)) {
      out[String(rawKey)] = Array.isArray(stack) ? [...stack] : [];
    }
    return out;
  }

  return {};
}

function deserializeSlots(rawSlots) {
  const map = new Map();
  if (!rawSlots || typeof rawSlots !== "object") return map;

  for (const [rawKey, stack] of Object.entries(rawSlots)) {
    const slotId = parseSlotIdString(rawKey);
    if (!slotId) continue;
    map.set(slotId, Array.isArray(stack) ? [...stack] : []);
  }
  return map;
}

function serializeGame(game) {
  if (!game || typeof game !== "object") return null;
  return {
    ...game,
    slots: serializeSlots(game.slots),
  };
}

function deserializeGame(rawGame) {
  if (!rawGame || typeof rawGame !== "object") return null;
  const slots = deserializeSlots(rawGame.slots);
  const cardsCount = rawGame.cardsById && typeof rawGame.cardsById === "object"
    ? Object.keys(rawGame.cardsById).length
    : 0;
  if (cardsCount > 0 && slots.size === 0) {
    console.warn("[SAVES] corrupted save ignored: slots empty while cards exist", { cardsCount });
    return null;
  }

  return {
    ...rawGame,
    slots,
  };
}

function saveGameState(game_id, game) {
  const all = loadSaves();
  const serializableGame = serializeGame(game);
  if (!serializableGame) return;
  all[game_id] = { game: serializableGame, savedAt: Date.now() };
  saveSaves(all);
}

function loadGameState(game_id) {
  const all = loadSaves();
  const rawGame = all[game_id]?.game ?? null;
  return deserializeGame(rawGame);
}

function deleteGameState(game_id) {
  const all = loadSaves();
  delete all[game_id];
  saveSaves(all);
}

export { saveGameState, loadGameState, deleteGameState };
