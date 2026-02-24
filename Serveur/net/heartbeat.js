// net/heartbeat.js - Gestion centralisee du heartbeat WebSocket

const DEFAULT_HEARTBEAT_CHECK_INTERVAL_MS = 5000;
const DEFAULT_HEARTBEAT_IDLE_BEFORE_PING_MS = 30000;
const DEFAULT_HEARTBEAT_TIMEOUT_MS = 8000;

function nowMs() {
  return Date.now();
}

/**
 * Marquer une connexion comme active via trafic applicatif (inbound/outbound)
 * @param {WebSocket} ws - Client WebSocket
 * @param {number} atMs - Timestamp de l'activite
 */
export function markHeartbeatActivity(ws, atMs = nowMs()) {
  if (!ws) return;
  ws.isAlive = true;
  ws.lastActivityAt = atMs;
  ws.awaitingHeartbeatProbe = false;
}

/**
 * Initialise les metadonnees heartbeat sur une connexion WebSocket
 * @param {WebSocket} ws - Client WebSocket
 */
export function initHeartbeat(ws) {
  const now = nowMs();
  ws.isAlive = true;
  ws.lastPing = now;
  ws.lastActivityAt = now;
  ws.awaitingHeartbeatProbe = false;
  ws.heartbeatProbeSentAt = 0;

  ws.on('pong', () => {
    const pongAt = nowMs();
    ws.lastPing = pongAt;
    markHeartbeatActivity(ws, pongAt);
  });
}

/**
 * Démarre le gestionnaire de heartbeat pour un serveur WebSocket.
 * Le ping n'est envoye qu'en cas d'inactivite prolongee.
 *
 * @param {WebSocketServer} wss - Serveur WebSocket
 * @param {Function} onClientDead - Callback quand un client ne répond pas
 * @param {number|Object} options - Nombre=checkIntervalMs ou options detaillees
 * @returns {NodeJS.Timer} Timer pour cleanup
 */
export function startHeartbeatManager(wss, onClientDead, options = {}) {
  const normalizedOptions = typeof options === "number"
    ? { checkIntervalMs: options }
    : (options ?? {});

  const checkIntervalMs = Number(
    normalizedOptions.checkIntervalMs ?? DEFAULT_HEARTBEAT_CHECK_INTERVAL_MS
  );
  const idleBeforePingMs = Number(
    normalizedOptions.idleBeforePingMs ?? DEFAULT_HEARTBEAT_IDLE_BEFORE_PING_MS
  );
  const heartbeatTimeoutMs = Number(
    normalizedOptions.heartbeatTimeoutMs ?? DEFAULT_HEARTBEAT_TIMEOUT_MS
  );

  const heartbeatTimer = setInterval(() => {
    const now = nowMs();
    for (const ws of wss.clients) {
      if (!ws || ws.readyState !== 1) continue;

      const lastActivityAt = Number(ws.lastActivityAt ?? now);
      if (ws.awaitingHeartbeatProbe) {
        const probeSentAt = Number(ws.heartbeatProbeSentAt ?? now);
        if (now - probeSentAt >= heartbeatTimeoutMs) {
          onClientDead?.(ws);
          ws.terminate();
        }
        continue;
      }

      // Trafic recent -> inutile de ping
      if (now - lastActivityAt < idleBeforePingMs) continue;

      ws.awaitingHeartbeatProbe = true;
      ws.heartbeatProbeSentAt = now;
      ws.isAlive = false;
      try {
        ws.ping();
      } catch {
        onClientDead?.(ws);
        ws.terminate();
      }
    }
  }, checkIntervalMs);

  if (typeof heartbeatTimer.unref === 'function') {
    heartbeatTimer.unref();
  }

  return heartbeatTimer;
}

/**
 * Arrête le gestionnaire de heartbeat
 * @param {NodeJS.Timer} heartbeatTimer - Timer retourné par startHeartbeatManager
 */
export function stopHeartbeatManager(heartbeatTimer) {
  if (heartbeatTimer) {
    clearInterval(heartbeatTimer);
  }
}

/**
 * Obtenir les constantes par défaut (utile pour tests/config)
 */
export function getHeartbeatConfig() {
  return {
    interval: DEFAULT_HEARTBEAT_CHECK_INTERVAL_MS,
    timeout: DEFAULT_HEARTBEAT_TIMEOUT_MS,
    idle_before_ping: DEFAULT_HEARTBEAT_IDLE_BEFORE_PING_MS,
  };
}
