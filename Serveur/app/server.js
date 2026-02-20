// server.js v3.0 - Refactorisé avec hearbeat + monitoring centralisés

import { WebSocketServer } from "ws";
import http from "http";

// ============= IMPORTS HANDLERS =============
import { handleLogin } from '../handlers/auth/login.js';
import { handleLogout } from '../handlers/auth/logout.js';
import { handleInvite, handleInviteResponse } from '../handlers/lobby/invite.js';
import { handleJoinGame } from '../handlers/game/joinGame.js';
import { handleSpectateGame } from '../handlers/game/spectateGame.js';
import { handleMoveRequest } from '../game/moveRequest.js';
import { handleLeaveGame, handleAckGameEnd } from '../handlers/game/gameEnd.js';

// ============= IMPORTS APP =============
import { createServerContext } from './context.js';
import { createRouter } from './router.js';
import { createWSManager } from '../net/wsManager.js';

// ============= IMPORTS NETWORK =============
import { stopHeartbeatManager } from '../net/heartbeat.js';
import { metrics, createMetricsMiddleware } from '../net/monitoring.js';

const DEBUG_TRACE_ENABLED = process.env.DEBUG_TRACE === "1";
const GAME_DEBUG_ENABLED = process.env.GAME_DEBUG === "1" || DEBUG_TRACE_ENABLED;

// ============= INITIALISATION =============

// 1️⃣ Créer le contexte (état + helpers)
const { baseCtx, loginCtx, onSocketClose } = createServerContext({
  onTransportSend: () => metrics.recordMessageSent(),
});

// 2️⃣ Créer le HTTP server (pour metrics + WebSocket)
const httpServer = http.createServer((req, res) => {
  // Health check + Metrics endpoint
  if (req.method === 'GET' && req.url === '/metrics') {
    const snapshot = metrics.getSnapshot();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(snapshot, null, 2));
    return;
  }

  // Health check simple
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', timestamp: new Date().toISOString() }));
    return;
  }

  // 404 pour tout le reste
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found' }));
});

// 3️⃣ Créer le websocket server attaché au HTTP server
const wss = new WebSocketServer({ server: httpServer });

// 4️⃣ Créer le wsManager
const wsManager = createWSManager({ wss, trace: console.log });

// 5️⃣ Créer le router (avec contexte + handlers)
const router = createRouter({
  state: baseCtx.state,
  sendRes: baseCtx.sendRes,
  wsManager,
  baseCtx,
  loginCtx,
  handleLogin,
  handleLogout,
  handleInvite,
  handleInviteResponse,
  handleJoinGame,
  handleSpectateGame,
  handleMoveRequest,
  handleLeaveGame,
  handleAckGameEnd,
  metrics, // Passer les métriques au router
});

// ============= WEBSOCKET EVENTS =============

wss.on("connection", async (ws) => {
  console.log("✅ Client connecté");
  metrics.recordConnection();
  
  // Init heartbeat + meta
  wsManager.initClient(ws);

  // Wrapper le onMessage avec metrics
  const onMessageWithMetrics = createMetricsMiddleware(
    (ws, msg) => router.onMessage(ws, msg),
    metrics
  );

  ws.on("message", async (msg) => {
    try {
      await onMessageWithMetrics(ws, msg.toString());
    } catch (err) {
      console.error("[MESSAGE_ERROR]", err);
    }
  });

  ws.on("close", () => {
    console.log("❌ Client déconnecté");
    metrics.recordDisconnection();
    wsManager.unregisterClient(ws);
    onSocketClose(ws);
  });

  ws.on("error", (err) => {
    console.error("[WS_ERROR]", err.message);
  });
});

// ============= HEARTBEAT =============
const heartbeatTimer = wsManager.startHeartbeat();

// ============= TURN EXPIRY LOOP =============
const TURN_EXPIRY_INTERVAL_MS = 250;
const turnExpiryTimer = setInterval(() => {
  const now = Date.now();
  for (const [game_id, game] of baseCtx.state.games.entries()) {
    if (!game?.turn) continue;
    try {
      baseCtx.processTurnTimeout?.(game_id, now);
    } catch (err) {
      console.error("[TURN_EXPIRY_ERROR]", { game_id, error: err?.message ?? String(err) });
    }
  }
}, TURN_EXPIRY_INTERVAL_MS);

if (typeof turnExpiryTimer.unref === "function") {
  turnExpiryTimer.unref();
}

// ============= GRACEFUL SHUTDOWN =============
process.on('SIGINT', () => {
  console.log('\n🛑 Shutting down...');
  stopHeartbeatManager(heartbeatTimer);
  clearInterval(turnExpiryTimer);
  wss.close(() => {
    httpServer.close(() => {
      console.log('Server closed');
      process.exit(0);
    });
  });
});

// ============= DÉMARRAGE =============
const PORT = process.env.WSS_PORT || 3000;
const HOST = "0.0.0.0";

httpServer.listen(PORT, HOST, () => {
  console.log(`🚀 Server listening on http://${HOST}:${PORT}`);
  console.log(`📊 Metrics available at http://${HOST}:${PORT}/metrics`);
  console.log(`❤️ Health check at http://${HOST}:${PORT}/health`);
  if (DEBUG_TRACE_ENABLED || GAME_DEBUG_ENABLED) {
    console.log(`🧪 Debug flags: DEBUG_TRACE=${DEBUG_TRACE_ENABLED ? "1" : "0"} GAME_DEBUG=${GAME_DEBUG_ENABLED ? "1" : "0"}`);
  }
});
