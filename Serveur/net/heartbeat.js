// net/heartbeat.js - Gestion centralisée du heartbeat WebSocket

const DEFAULT_HEARTBEAT_INTERVAL_MS = 5000;
const DEFAULT_HEARTBEAT_TIMEOUT_MS = 5000;

/**
 * Initialise le heartbeat sur une connexion WebSocket
 * @param {WebSocket} ws - Client WebSocket
 */
export function initHeartbeat(ws) {
  ws.isAlive = true;
  ws.lastPing = Date.now();

  ws.on('pong', () => {
    ws.isAlive = true;
    ws.lastPing = Date.now();
  });
}

/**
 * Démarre le gestionnaire de heartbeat pour un serveur WebSocket
 * @param {WebSocketServer} wss - Serveur WebSocket
 * @param {Function} onClientDead - Callback quand un client ne répond pas
 * @param {number} heartbeatInterval - Intervalle de heartbeat en ms (défaut: 30s)
 * @returns {NodeJS.Timer} Timer pour cleanup
 */
export function startHeartbeatManager(
  wss,
  onClientDead,
  heartbeatInterval = DEFAULT_HEARTBEAT_INTERVAL_MS
) {
  const heartbeatTimer = setInterval(() => {
    for (const ws of wss.clients) {
      if (!ws.isAlive) {
        // Client n'a pas répondu au ping précédent
        onClientDead?.(ws);
        ws.terminate();
        continue;
      }

      // Marquer comme non-vivant et envoyer un ping
      ws.isAlive = false;
      ws.ping();
    }
  }, heartbeatInterval);

  // Permet au processus Node de se terminer sans attendre ce timer
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
    interval: DEFAULT_HEARTBEAT_INTERVAL_MS,
    timeout: DEFAULT_HEARTBEAT_TIMEOUT_MS,
  };
}
