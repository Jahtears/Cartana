// net/wsManager.js v2.0 - Gestion des métadonnées de connexion
// Le heartbeat est maintenant centralisé dans heartbeat.js

import { initHeartbeat, startHeartbeatManager } from './heartbeat.js';

export function createWSManager({ wss, trace }) {
  const clientMeta = new Map(); // ws => {username, connected_at, lastPing}

  /**
   * Initialise une nouvelle connexion client
   * @param {WebSocket} ws - Client WebSocket
   */
  function initClient(ws) {
    // Initialiser le heartbeat
    initHeartbeat(ws);
    
    // Mémoriser les métadonnées
    clientMeta.set(ws, {
      connected_at: Date.now(),
      lastPing: Date.now(),
      username: null
    });
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
      trace?.('HEARTBEAT_TIMEOUT', { username: meta?.username ?? 'unknown' });
    });
  }

  /**
   * Compter les clients actifs
   * @returns {number} Nombre de clients
   */
  function getClientCount() {
    return clientMeta.size;
  }

  /**
   * Obtenir les métadonnées d'un client
   * @param {WebSocket} ws - Client WebSocket
   * @returns {Object} Métadonnées du client
   */
  function getClientMeta(ws) {
    return clientMeta.get(ws);
  }

  return {
    initClient,
    registerUsername,
    unregisterClient,
    startHeartbeat,
    getClientCount,
    getClientMeta,
  };
}