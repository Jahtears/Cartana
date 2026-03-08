// handlers/login.js v2.1
import { resError } from "../../net/transport.js";
import { POPUP_MESSAGE } from "../../shared/popupMessages.js";

const LOGIN_RATE_MAX_ATTEMPTS = parsePositiveInt(
  process.env.LOGIN_RATE_MAX_ATTEMPTS,
  5
);
const LOGIN_RATE_WINDOW_MS = parsePositiveInt(
  process.env.LOGIN_RATE_WINDOW_MS,
  60_000
);
const LOGIN_RATE_BLOCK_MS = parsePositiveInt(
  process.env.LOGIN_RATE_BLOCK_MS,
  5 * 60_000
);
const LOGIN_RATE_SWEEP_EVERY = 100;
const LOGIN_RATE_BUCKET_TTL_MS =
  Math.max(LOGIN_RATE_WINDOW_MS, LOGIN_RATE_BLOCK_MS) * 2;

const loginRateBuckets = new Map();
let loginRateOpCount = 0;

function parsePositiveInt(rawValue, fallback) {
  const value = Number.parseInt(String(rawValue ?? ""), 10);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

function normalizePart(value) {
  return String(value ?? "").trim().toLowerCase();
}

function getRemoteAddress(ws) {
  const fromSocket = ws?._socket?.remoteAddress;
  const fromUpgradeReq = ws?.upgradeReq?.socket?.remoteAddress;
  return normalizePart(fromSocket || fromUpgradeReq || "");
}

function buildLoginRateKeys(ws, username) {
  const user = normalizePart(username);
  const ip = getRemoteAddress(ws);

  if (ip && user) return [`ip:${ip}`, `ip_user:${ip}|${user}`];
  if (ip) return [`ip:${ip}`];
  if (user) return [`user:${user}`];
  return [];
}

function pruneFailures(bucket, nowMs) {
  const cutoff = nowMs - LOGIN_RATE_WINDOW_MS;
  while (bucket.failures.length > 0 && bucket.failures[0] < cutoff) {
    bucket.failures.shift();
  }
}

function getOrCreateBucket(key, nowMs) {
  let bucket = loginRateBuckets.get(key);
  if (!bucket) {
    bucket = { failures: [], blockedUntil: 0, lastSeen: nowMs };
    loginRateBuckets.set(key, bucket);
  }
  bucket.lastSeen = nowMs;
  return bucket;
}

function maybeSweepBuckets(nowMs) {
  loginRateOpCount += 1;
  if (loginRateOpCount % LOGIN_RATE_SWEEP_EVERY !== 0) return;

  for (const [key, bucket] of loginRateBuckets) {
    pruneFailures(bucket, nowMs);
    const blocked = bucket.blockedUntil > nowMs;
    const stale = nowMs - bucket.lastSeen > LOGIN_RATE_BUCKET_TTL_MS;
    if ((!blocked && bucket.failures.length === 0) || stale) {
      loginRateBuckets.delete(key);
    }
  }
}

function getRetryAfterMs(keys, nowMs = Date.now()) {
  if (!Array.isArray(keys) || keys.length === 0) return 0;
  maybeSweepBuckets(nowMs);

  let retryAfter = 0;
  for (const key of keys) {
    const bucket = loginRateBuckets.get(key);
    if (!bucket) continue;
    bucket.lastSeen = nowMs;
    pruneFailures(bucket, nowMs);

    if (bucket.blockedUntil > nowMs) {
      retryAfter = Math.max(retryAfter, bucket.blockedUntil - nowMs);
      continue;
    }

    if (bucket.failures.length === 0) {
      loginRateBuckets.delete(key);
    }
  }
  return retryAfter;
}

function retryAfterSeconds(retryAfterMs) {
  const safeMs = Math.max(0, Number(retryAfterMs) || 0);
  return Math.max(1, Math.ceil(safeMs / 1000));
}

function buildMaxTryError(retryAfterMs) {
  const safeMs = Math.max(0, Number(retryAfterMs) || 0);
  const retryAfterS = retryAfterSeconds(safeMs);
  return {
    message_code: POPUP_MESSAGE.AUTH_MAX_TRY,
    message_params: { retry_after_s: retryAfterS },
    details: { retry_after_ms: safeMs },
  };
}

function recordLoginFailure(keys, nowMs = Date.now()) {
  if (!Array.isArray(keys) || keys.length === 0) return 0;
  maybeSweepBuckets(nowMs);

  let retryAfter = 0;
  for (const key of keys) {
    const bucket = getOrCreateBucket(key, nowMs);
    pruneFailures(bucket, nowMs);
    bucket.failures.push(nowMs);

    if (bucket.failures.length >= LOGIN_RATE_MAX_ATTEMPTS) {
      bucket.blockedUntil = Math.max(bucket.blockedUntil, nowMs + LOGIN_RATE_BLOCK_MS);
      bucket.failures.length = 0;
      retryAfter = Math.max(retryAfter, bucket.blockedUntil - nowMs);
    }
  }
  return retryAfter;
}

function clearLoginFailures(keys) {
  if (!Array.isArray(keys) || keys.length === 0) return;
  for (const key of keys) {
    loginRateBuckets.delete(key);
  }
}

export function resetLoginRateLimiterForTests() {
  loginRateBuckets.clear();
  loginRateOpCount = 0;
}

export async function handleLogin(ctx, ws, req, data) {
  const {
    state,
    verifyOrCreateUser,
    getUserStatus,
    sendRes,
    refreshLobby,
    handleReconnect,
  } = ctx;

  // Safely handle undefined data
  const safeData = data ?? {};
  const username = String(safeData.username ?? "").trim();
  const pin = String(safeData.pin ?? "").trim();
  const rateLimitKeys = buildLoginRateKeys(ws, username);

  if (!username || !pin) {
    resError(sendRes, ws, req, POPUP_MESSAGE.AUTH_MISSING_CREDENTIALS);
    return true;
  }

  const retryAfterMs = getRetryAfterMs(rateLimitKeys);
  if (retryAfterMs > 0) {
    sendRes(ws, req, false, buildMaxTryError(retryAfterMs));
    return true;
  }

  try {
    const ok = await verifyOrCreateUser(username, pin);
    if (!ok) {
      const blockedForMs = recordLoginFailure(rateLimitKeys);
      if (blockedForMs > 0) {
        sendRes(ws, req, false, buildMaxTryError(blockedForMs));
      } else {
        sendRes(ws, req, false, {
          message_code: POPUP_MESSAGE.AUTH_BAD_PIN,
        });
      }
      return true;
    }

    clearLoginFailures(rateLimitKeys);

    const existingWs = state.getWS(username);
    console.log('[LOGIN] Checking if user already connected:', { username, hasExistingWs: !!existingWs, isSameWs: existingWs === ws });
    
    // Si l'utilisateur a déjà un websocket différent (reconnexion), on ferme proprement l'ancien
    if (existingWs && existingWs !== ws) {
      console.log('[LOGIN] Reconnection detected, closing old websocket for:', username);
      try {
        existingWs.close(1000, 'Reconnection from new client');
      } catch (err) {
        console.warn('[LOGIN] Failed to close old websocket:', err.message);
      }
      // Nettoyer l'ancien mapping immédiatement
      state.unregisterUser(username, existingWs);
    }

    state.registerUser(username, ws);

    // Reconnexion: restaurer présence in-game si mapping existant.
    if (typeof handleReconnect === "function") {
      handleReconnect(username);
    }

    sendRes(ws, req, true, { username, status: getUserStatus(username) });
    if (typeof refreshLobby === "function") refreshLobby();
    return true;

  } catch (err) {
    console.error("Erreur login:", err);
    resError(sendRes, ws, req, POPUP_MESSAGE.TECH_INTERNAL_ERROR);
    return true;
  }
}
