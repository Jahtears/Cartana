// net/wsManager.js v2.0 - Gestion des métadonnées de connexion
// Le heartbeat est maintenant centralisé dans heartbeat.js

import {
  initHeartbeat,
  markHeartbeatActivity,
  startHeartbeatManager,
} from './heartbeat.js';

export function createWSManager({ wss, trace }) {
  const clientMeta = new Map(); // ws => {username, connected_at, lastActivityAt}

  /**
   * Initialise une nouvelle connexion client
   * @param {WebSocket} ws - Client WebSocket
   */
  function initClient(ws) {
    // Initialiser le heartbeat
    initHeartbeat(ws);
    ws.on?.('pong', () => markActivity(ws, "pong"));

    const now = Date.now();
    // Mémoriser les métadonnées
    clientMeta.set(ws, {
      connected_at: now,
      lastPing: now,
      lastActivityAt: now,
      lastActivitySource: "connect",
      username: null
    });
  }

  /**
   * Marquer une activité réseau sur la connexion
   * @param {WebSocket} ws - Client WebSocket
   * @param {string} source - Source de l'activité (inbound/outbound/pong)
   */
  function markActivity(ws, source = "inbound") {
    const now = Date.now();
    const confirmsAlive = source === "inbound" || source === "pong";
    if (confirmsAlive) {
      markHeartbeatActivity(ws, now);
    }
    const meta = clientMeta.get(ws);
    if (!meta) return;
    meta.lastActivityAt = now;
    meta.lastActivitySource = source;
    if (source === "pong") {
      meta.lastPing = now;
    }
  }

  /**
   * Enregistrer l'identifiant d'un client après authentification
   * @param {WebSocket} ws - Client WebSocket
   * @param {string} username - Nom d'utilisateur
   */
  function registerUsername(ws, username) {
    const meta = clientMeta.get(ws);
    if (meta) meta.username = username;
  }

  /**
   * Désenregistrer un client lors de la déconnexion
   * @param {WebSocket} ws - Client WebSocket
   */
  function unregisterClient(ws) {
    clientMeta.delete(ws);
  }

  /**
   * Lancer le gestionnaire de heartbeat global
   * @returns {NodeJS.Timer} Timer pour cleanup
   */
  function startHeartbeat() {
    return startHeartbeatManager(wss, (ws) => {
      const meta = clientMeta.get(ws);
      trace?.('HEARTBEAT_TIMEOUT', {
        username: meta?.username ?? 'unknown',
        lastActivityAt: meta?.lastActivityAt ?? null,
      });
    });
  }

  return {
    initClient,
    markActivity,
    registerUsername,
    unregisterClient,
    startHeartbeat,
  };
}
