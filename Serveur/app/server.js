// server.js v3.0 - Refactorisé avec hearbeat + monitoring centralisés

import { WebSocketServer } from "ws";
import http from "http";
import https from "https";
import fs from "fs";

// ============= IMPORTS HANDLERS =============
import { handleLogin } from '../handlers/auth/login.js';
import { handleLogout } from '../handlers/auth/logout.js';
import { handleInvite, handleInviteResponse } from '../handlers/lobby/invite.js';
import { handleGetLeaderboard } from '../handlers/lobby/leaderboard.js';
import { handleJoinGame } from '../handlers/game/joinGame.js';
import { handleSpectateGame } from '../handlers/game/spectateGame.js';
import { handleMoveRequest } from '../handlers/game/moveRequest.js';
import { handleLeaveGame, handleAckGameEnd } from '../handlers/game/gameEnd.js';

// ============= IMPORTS APP =============
import { createServerContext } from './context.js';
import { createRouter } from './router.js';
import { createWSManager } from '../net/wsManager.js';

// ============= IMPORTS NETWORK =============
import { stopHeartbeatManager } from '../net/heartbeat.js';
import { metrics, createMetricsMiddleware } from '../net/monitoring.js';

const DEBUG_TRACE_ENABLED = process.env.DEBUG_TRACE === "1";
const SERVER_MODE = String(process.env.SERVER_MODE ?? "tls_direct").trim().toLowerCase();
const BACKEND_HTTP_MODE = SERVER_MODE === "backend_http";
const TLS_CERT_PATH = String(process.env.TLS_CERT_PATH ?? "").trim();
const TLS_KEY_PATH = String(process.env.TLS_KEY_PATH ?? "").trim();

if (!BACKEND_HTTP_MODE && (TLS_CERT_PATH === "" || TLS_KEY_PATH === "")) {
  throw new Error("TLS required: set both TLS_CERT_PATH and TLS_KEY_PATH");
}

// ============= INITIALISATION =============

let wsManager = null;

// 1️⃣ Créer le contexte (état + helpers)
const { baseCtx, loginCtx, onSocketClose } = createServerContext({
  onTransportSend: (ws) => {
    metrics.recordMessageSent();
    wsManager?.markActivity(ws, "outbound");
  },
});

function requestHandler(req, res) {
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
}

// 2️⃣ Créer le serveur de transport (HTTP local backend, ou HTTPS direct)
let transportServer;
if (BACKEND_HTTP_MODE) {
  transportServer = http.createServer(requestHandler);
} else {
  try {
    transportServer = https.createServer(
      {
        cert: fs.readFileSync(TLS_CERT_PATH),
        key: fs.readFileSync(TLS_KEY_PATH),
      },
      requestHandler
    );
  } catch (err) {
    console.error("[TLS_CONFIG_ERROR]", err?.message ?? String(err));
    process.exit(1);
  }
}

// 3️⃣ Créer le websocket server attaché au server de transport
const wss = new WebSocketServer({ server: transportServer });

// 4️⃣ Créer le wsManager
wsManager = createWSManager({ wss, trace: console.log });

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
  handleGetLeaderboard,
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
      wsManager.markActivity(ws, "inbound");
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
      baseCtx.usecases?.turn?.processTurnTimeout?.(game_id, now);
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
    transportServer.close(() => {
      console.log('Server closed');
      process.exit(0);
    });
  });
});

// ============= DÉMARRAGE =============
const PORT = BACKEND_HTTP_MODE
  ? Number(process.env.BACKEND_PORT ?? 3001)
  : Number(process.env.WSS_PORT ?? 3000);
const HOST = BACKEND_HTTP_MODE ? "127.0.0.1" : "0.0.0.0";

transportServer.listen(PORT, HOST, () => {
  if (BACKEND_HTTP_MODE) {
    console.log(`🚀 Backend listening on http://${HOST}:${PORT}`);
    console.log(`🔌 Internal WebSocket endpoint ws://${HOST}:${PORT}`);
    console.log(`📊 Internal metrics at http://${HOST}:${PORT}/metrics`);
    console.log(`❤️ Internal health at http://${HOST}:${PORT}/health`);
  } else {
    console.log(`🚀 Server listening on https://${HOST}:${PORT}`);
    console.log(`🔌 WebSocket endpoint wss://${HOST}:${PORT}`);
    console.log(`📊 Metrics available at https://${HOST}:${PORT}/metrics`);
    console.log(`❤️ Health check at https://${HOST}:${PORT}/health`);
  }
  if (DEBUG_TRACE_ENABLED || process.env.GAME_DEBUG === "1") {
    console.log(`🧪 Debug flags: DEBUG_TRACE=${DEBUG_TRACE_ENABLED ? "1" : "0"} GAME_DEBUG=${process.env.GAME_DEBUG === "1" || DEBUG_TRACE_ENABLED ? "1" : "0"}`);
  }
});
