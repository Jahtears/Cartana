import { GAME_END_REASONS, normalizeGameEndReason } from "./constants/gameEnd.js";

// meta.js

export function ensureGameMeta(gameMeta, gameId, { initialSent } = {}) {
  let meta = gameMeta.get(gameId);

  if (!meta || typeof meta !== "object") meta = {};

  if (!(meta.disconnected instanceof Set)) meta.disconnected = new Set();
  if (!meta.lastSeen || typeof meta.lastSeen !== "object") meta.lastSeen = Object.create(null);
  if (typeof meta.createdAt !== "number" || !Number.isFinite(meta.createdAt)) meta.createdAt = Date.now();

  if (typeof meta.initialSent !== "boolean") meta.initialSent = false;
  if (typeof initialSent === "boolean") meta.initialSent = meta.initialSent || initialSent;

  meta.slot_sig ??= Object.create(null);
  meta.turn_sig ??= "";

  if (!("result" in meta)) meta.result = null;

  gameMeta.set(gameId, meta);
  return meta;
}

export function ensureGameResult(meta, patch = {}) {
  const now = Date.now();
  const p = patch && typeof patch === "object" ? patch : {};
  const patchReason = normalizeGameEndReason(p.reason, GAME_END_REASONS.ABANDON);

  const normalized = (r) => {
    const e = r && typeof r === "object" ? r : {};

    if (typeof e.winner === "undefined") e.winner = "winner" in p ? p.winner : null;

    if (typeof e.reason !== "string" || !e.reason) {
      e.reason = patchReason;
    } else {
      e.reason = normalizeGameEndReason(e.reason, e.reason);
    }

    if (typeof e.by !== "string" || !e.by)
      e.by = typeof p.by === "string" && p.by ? p.by : "";

    if (typeof e.at !== "number" || !Number.isFinite(e.at))
      e.at = typeof p.at === "number" && Number.isFinite(p.at) ? p.at : now;

    return e;
  };

  let created = false;
  if (!meta.result) {
    meta.result = normalized(null);
    created = true;
  } else {
    meta.result = normalized(meta.result);
  }

  return { result: meta.result, created };
}
