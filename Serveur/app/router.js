// router.js v2.0 

import { POPUP_MESSAGE } from "../shared/popupMessages.js";
const DEV_TRACE = process.env.DEBUG_TRACE === "1";
const RID_CACHE_LIMIT = 200;

function withTrace(baseCtx, req) {
  if (!DEV_TRACE) return baseCtx;
  const traceId = `${req.type}#${req.rid}`;
  const ctx = Object.create(baseCtx);
  ctx.traceId = traceId;
  ctx.trace = (...args) => console.log("[TRACE]", traceId, ...args);
  return ctx;
}

function requireAuth(ws, req, { state, sendRes }) {
  const user = state.getUsername(ws);
  if (!user) {
    sendRes(ws, req, false, {
      message_code: POPUP_MESSAGE.AUTH_REQUIRED,
    });
    return null;
  }
  return user;
}

function ensureRidState(byWs, ws) {
  let state = byWs.get(ws);
  if (!state) {
    state = {
      inFlight: new Set(),
      responses: new Map(),
    };
    byWs.set(ws, state);
  }
  return state;
}

function trimRidCache(responses) {
  while (responses.size > RID_CACHE_LIMIT) {
    const oldestRid = responses.keys().next().value;
    responses.delete(oldestRid);
  }
}

export function createRouter({
  // state
  state,

  // transport
  sendRes,
  wsManager,

  // base context
  baseCtx,
  loginCtx,

  // handlers
  handleLogin,
  handleLogout,
  handleInvite,
  handleInviteResponse,
  handleJoinGame,
  handleSpectateGame,
  handleMoveRequest,
  handleLeaveGame,
  handleAckGameEnd,

  // metrics (optional)
  metrics,
}) {
  const ridStateByWs = new WeakMap();

  async function onMessage(ws, rawMsg) {
    let env;
    try {
      env = JSON.parse(rawMsg);
    } catch {
      return;
    }

    if (
      !env ||
      env.v !== 1 ||
      env.kind !== "req" ||
      typeof env.type !== "string" ||
      typeof env.rid !== "string"
    ) {
      return;
    }

    const req = env;
    const data = req.data ?? {};
    const ridState = ensureRidState(ridStateByWs, ws);

    const cached = ridState.responses.get(req.rid);
    if (cached && cached.type === req.type) {
      sendRes(ws, req, cached.ok, cached.payload);
      return;
    }

    if (ridState.inFlight.has(req.rid)) {
      return;
    }
    ridState.inFlight.add(req.rid);

    const sendResWithRidCache = (targetWs, targetReq, ok, payload) => {
      if (
        targetWs === ws &&
        targetReq &&
        String(targetReq.rid) === String(req.rid)
      ) {
        ridState.responses.set(req.rid, {
          type: String(targetReq.type ?? ""),
          ok: !!ok,
          payload,
        });
        trimRidCache(ridState.responses);
      }
      return sendRes(targetWs, targetReq, ok, payload);
    };

    try {
      // ---------- LOGIN (pas d'auth requise) ----------
      if (req.type === "login") {
        try {
          const loginCtxWithCache = Object.create(loginCtx);
          loginCtxWithCache.sendRes = sendResWithRidCache;
          const result = await handleLogin(loginCtxWithCache, ws, req, data ?? {});
          if (result) {
            // Enregistrer username dans wsManager après login
            const user = state.getUsername(ws);
            if (user && wsManager) {
              wsManager.registerUsername(ws, user);
            }
          }
          return;
        } catch (err) {
          console.error("[ROUTE_ERROR] login", err);
          sendResWithRidCache(ws, req, false, {
            message_code: POPUP_MESSAGE.TECH_INTERNAL_ERROR,
          });
          return;
        }
      }

      // ---------- Tout le reste nécessite auth ----------
      const actor = requireAuth(ws, req, { state, sendRes: sendResWithRidCache });
      if (!actor) return;

      const ctx = withTrace(baseCtx, req);
      ctx.sendRes = sendResWithRidCache;

      // ✅ Routes mapping (handlers externes)
      const routes = {
        ping: async () => {
          sendResWithRidCache(ws, req, true, { server_ms: Date.now() });
        },

        get_players: async () => {
          ctx.trace?.("get_players");
          sendResWithRidCache(ws, req, true, {
            players: ctx.playersList?.() ?? [],
            statuses: ctx.playersStatuses?.() ?? {},
            games: ctx.gamesList?.() ?? [],
          });
        },

        logout: async () => handleLogout(ctx, ws, req, data, actor),
        invite: async () => handleInvite(ctx, ws, req, data, actor),
        invite_response: async () => handleInviteResponse(ctx, ws, req, data, actor),
        join_game: async () => handleJoinGame(ctx, ws, req, data, actor),
        spectate_game: async () => handleSpectateGame(ctx, ws, req, data, actor),
        move_request: async () => handleMoveRequest(ctx, ws, req, data, actor),
        leave_game: async () => handleLeaveGame(ctx, ws, req, data, actor),
        ack_game_end: async () => handleAckGameEnd(ctx, ws, req, data, actor),
      };

      const fn = routes[req.type];
      if (!fn) {
        sendResWithRidCache(ws, req, false, {
          message_code: POPUP_MESSAGE.TECH_NOT_IMPLEMENTED,
        });
        return;
      }

      try {
        const t0 = DEV_TRACE ? Date.now() : 0;
        ctx.trace?.("BEGIN", { actor });
        await fn();
        ctx.trace?.("END", { ms: Date.now() - t0 });
      } catch (err) {
        console.error("[ROUTE_ERROR]", req.type, err);
        ctx.trace?.("ERROR", String(err?.message ?? err));
        sendResWithRidCache(ws, req, false, {
          message_code: POPUP_MESSAGE.TECH_INTERNAL_ERROR,
        });
      }
    } finally {
      ridState.inFlight.delete(req.rid);
    }
  }

  return { onMessage };
}
