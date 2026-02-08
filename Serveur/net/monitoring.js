// net/monitoring.js - Métriques et observabilité

/**
 * Gestionnaire de métriques pour le serveur WebSocket
 */
export class Metrics {
  constructor() {
    this.wsConnections = 0;
    this.totalMessagesReceived = 0;
    this.totalMessagesSent = 0;
    this.gamesActive = 0;
    this.startTime = Date.now();
    this.messagesByType = {}; // type => count
  }

  /**
   * Enregistrer une nouvelle connexion
   */
  recordConnection() {
    this.wsConnections++;
  }

  /**
   * Enregistrer une déconnexion
   */
  recordDisconnection() {
    if (this.wsConnections > 0) {
      this.wsConnections--;
    }
  }

  /**
   * Enregistrer un message reçu
   * @param {string} type - Type de message
   */
  recordMessageReceived(type) {
    this.totalMessagesReceived++;
    this.messagesByType[type] = (this.messagesByType[type] ?? 0) + 1;
  }

  /**
   * Enregistrer un message envoyé
   */
  recordMessageSent() {
    this.totalMessagesSent++;
  }

  /**
   * Mettre à jour le nombre de jeux actifs
   * @param {number} count - Nombre de jeux
   */
  setGamesActive(count) {
    this.gamesActive = count;
  }

  /**
   * Calculer les messages par seconde
   * @returns {number} Messages par seconde
   */
  getMessagesPerSecond() {
    const elapsed = (Date.now() - this.startTime) / 1000;
    if (elapsed === 0) return 0;
    return Math.round((this.totalMessagesSent + this.totalMessagesReceived) / elapsed * 100) / 100;
  }

  /**
   * Obtenir les uptime en secondes
   * @returns {number} Uptime en secondes
   */
  getUptimeSeconds() {
    return Math.floor((Date.now() - this.startTime) / 1000);
  }

  /**
   * Obtenir un snapshot de toutes les métriques
   * @returns {Object} Snapshot JSON
   */
  getSnapshot() {
    const uptimeSeconds = this.getUptimeSeconds();
    return {
      timestamp: new Date().toISOString(),
      uptime_seconds: uptimeSeconds,
      ws_connections: this.wsConnections,
      total_messages_received: this.totalMessagesReceived,
      total_messages_sent: this.totalMessagesSent,
      messages_per_second: this.getMessagesPerSecond(),
      games_active: this.gamesActive,
      messages_by_type: { ...this.messagesByType },
    };
  }

  /**
   * Réinitialiser les métriques (pour tests)
   */
  reset() {
    this.wsConnections = 0;
    this.totalMessagesReceived = 0;
    this.totalMessagesSent = 0;
    this.gamesActive = 0;
    this.startTime = Date.now();
    this.messagesByType = {};
  }
}

// Instance globale de métriques
export const metrics = new Metrics();

/**
 * Middleware pour enregistrer les messages
 * @param {Function} onMessage - Handler de message original
 * @param {Metrics} metricsInstance - Instance de métriques
 * @returns {Function} Middleware
 */
export function createMetricsMiddleware(onMessage, metricsInstance = metrics) {
  return async (ws, rawMsg) => {
    let env;
    try {
      env = JSON.parse(rawMsg);
    } catch {
      return;
    }

    // Enregistrer le message
    if (env.type) {
      metricsInstance.recordMessageReceived(env.type);
    }

    // Appeler le handler original
    return onMessage(ws, rawMsg);
  };
}
