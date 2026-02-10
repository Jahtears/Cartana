// router.js v2.0 

const DEV_TRACE = process.env.DEBUG_TRACE === "1";

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
    sendRes(ws, req, false, { code: "AUTH_REQUIRED", message: "Non authentifié" });
    return null;
  }
  return user;
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
  handleReadyForGame,
  handleJoinGame,
  handleSpectateGame,
  handleMoveRequest,
  handleLeaveGame,
  handleAckGameEnd,

  // metrics (optional)
  metrics,
}) {
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

    // ---------- LOGIN (pas d'auth requise) ----------
    if (req.type === "login") {
      try {
        const result = await handleLogin(loginCtx, ws, req, data ?? {});
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
        sendRes(ws, req, false, { code: "SERVER_ERROR", message: "Erreur serveur" });
        return;
      }
    }

    // ---------- Tout le reste nécessite auth ----------
    const actor = requireAuth(ws, req, { state, sendRes });
    if (!actor) return;

    const ctx = withTrace(baseCtx, req);

    // ✅ Routes mapping (handlers externes)
    const routes = {
      get_players: async () => {
        ctx.trace?.("get_players");
        sendRes(ws, req, true, {
          players: ctx.playersList?.() ?? [],
          statuses: ctx.playersStatuses?.() ?? {},
          games: ctx.gamesList?.() ?? [],
        });
      },

      logout: async () => handleLogout(ctx, ws, req, data, actor),
      invite: async () => handleInvite(ctx, ws, req, data, actor),
      invite_response: async () => handleInviteResponse(ctx, ws, req, data, actor),
      ready_for_game: async () => handleReadyForGame(ctx, ws, req, data, actor),
      join_game: async () => handleJoinGame(ctx, ws, req, data, actor),
      spectate_game: async () => handleSpectateGame(ctx, ws, req, data, actor),
      move_request: async () => handleMoveRequest(ctx, ws, req, data, actor),
      leave_game: async () => handleLeaveGame(ctx, ws, req, data, actor),
      ack_game_end: async () => handleAckGameEnd(ctx, ws, req, data, actor),
    };

    const fn = routes[req.type];
    if (!fn) {
      sendRes(ws, req, false, { code: "NOT_IMPLEMENTED", message: `Type non géré: ${req.type}` });
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
      sendRes(ws, req, false, { code: "SERVER_ERROR", message: "Erreur serveur" });
    }
  }

  return { onMessage };
}
