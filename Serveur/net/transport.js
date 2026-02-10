// net/transport.js v3.0 - Transport et réponses
// Le heartbeat est maintenant centralisé dans heartbeat.js

/**
 * Vérifier si un WebSocket est ouvert
 */
function wsIsOpen(ws) {
  return !!ws && ws.readyState === 1;
}

/**
 * Envoyer un message brut de manière sûre
 * @param {WebSocket} ws - Client WebSocket
 * @param {Object} envelope - Enveloppe de message
 * @returns {boolean} true si envoyé, false sinon
 */
function safeSend(ws, envelope) {
  if (!wsIsOpen(ws)) return false;
  try {
    ws.send(JSON.stringify(envelope));
    return true;
  } catch {
    return false;
  }
}

/**
 * Créer le transport (fonctions d'envoi)
 * @param {Object} config - {wsByUser}
 * @returns {Object} Transport avec API V2
 */
export function createTransport({ wsByUser }) {
  /**
   * Envoyer une réponse à une requête
   * @param {WebSocket} ws - Client WebSocket
   * @param {Object} req - Requête originale
   * @param {boolean} ok - Succès/Erreur
   * @param {Object} payload - Données ou erreur
   */
  function sendRes(ws, req, ok, payload) {
    const base = { v: 1, kind: "res", type: req.type, rid: req.rid, ok: !!ok };
    if (ok) return safeSend(ws, { ...base, data: payload ?? {} });
    return safeSend(ws, { ...base, error: payload ?? { code: "UNKNOWN", message: "Erreur" } });
  }

  /**
   * Envoyer un événement à un client
   * @param {WebSocket} ws - Client WebSocket
   * @param {string} type - Type d'événement
   * @param {Object} data - Données de l'événement
   */
  function sendEvtSocket(ws, type, data) {
    return safeSend(ws, { v: 1, kind: "evt", type, data: data ?? {} });
  }

  /**
   * Envoyer un événement à un utilisateur par son nom
   * @param {string} username - Nom d'utilisateur
   * @param {string} type - Type d'événement
   * @param {Object} data - Données de l'événement
   */
  function sendEvtUser(username, type, data) {
    const ws = wsByUser.get(username);
    return sendEvtSocket(ws, type, data);
  }

  /**
   * Envoyer un événement à tous les utilisateurs du lobby
   * @param {string} type - Type d'événement
   * @param {Object} data - Données de l'événement
   */
  function sendEvtLobby(type, data) {
    for (const ws of wsByUser.values()) sendEvtSocket(ws, type, data);
  }

  return { 
    sendRes,
    sendEvtSocket,
    sendEvtUser,
    sendEvtLobby,
    safeSend, // Exporter pour usage interne si needed
    wsIsOpen,  // Exporter pour vérifications
  };
}

/* -------------------------------------------------------
   Error Helpers
   Conventions: retournent true (pratique: `return resNotFound(...)`)
-------------------------------------------------------- */

/**
 * Envoyer une erreur
 * @param {Function} sendRes - Fonction sendRes
 * @param {WebSocket} ws - Client WebSocket
 * @param {Object} req - Requête originale
 * @param {string} code - Code d'erreur
 * @param {string} message - Message d'erreur
 * @param {Object} details - Détails additionnels
 */
export function resError(sendRes, ws, req, code, message, details) {
   const error = { code, message };
   if (details && typeof details === "object") error.details = details;
   sendRes(ws, req, false, error);
   return true;
}

export function resBadRequest(sendRes, ws, req, message = "BAD_REQUEST", details) {
  return resError(sendRes, ws, req, "BAD_REQUEST", message, details);
}

export function resNotFound(sendRes, ws, req, message = "NOT_FOUND", details) {
  return resError(sendRes, ws, req, "NOT_FOUND", message, details);
}

export function resForbidden(sendRes, ws, req, message = "FORBIDDEN", details) {
  return resError(sendRes, ws, req, "FORBIDDEN", message, details);
}

export function resBadState(sendRes, ws, req, message = "BAD_STATE", details) {
  return resError(sendRes, ws, req, "BAD_STATE", message, details);
}

export function resGameEnd(sendRes, ws, req, message = "Partie terminée", details) {
  return resError(sendRes, ws, req, "GAME_END", message, details);
}

export function resNotImplemented(sendRes, ws, req, message = "Type non géré", details) {
  return resError(sendRes, ws, req, "NOT_IMPLEMENTED", message, details);
}

export function resServerError(sendRes, ws, req, message = "Erreur serveur", details) {
  return resError(sendRes, ws, req, "SERVER_ERROR", message, details);
}
