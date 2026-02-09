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
 * @returns {Object} Transport avec sendResponse, sendEvent, etc.
 */
export function createTransport({ wsByUser }) {
  /**
   * Envoyer une réponse à une requête
   * @param {WebSocket} ws - Client WebSocket
   * @param {Object} req - Requête originale
   * @param {boolean} ok - Succès/Erreur
   * @param {Object} payload - Données ou erreur
   */
  function sendResponse(ws, req, ok, payload) {
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
  function sendEvent(ws, type, data) {
    return safeSend(ws, { v: 1, kind: "evt", type, data: data ?? {} });
  }

  /**
   * Envoyer un événement à un utilisateur par son nom
   * @param {string} username - Nom d'utilisateur
   * @param {string} type - Type d'événement
   * @param {Object} data - Données de l'événement
   */
  function sendEventToUser(username, type, data) {
    const ws = wsByUser.get(username);
    return sendEvent(ws, type, data);
  }

  /**
   * Envoyer un événement à tous les utilisateurs du lobby
   * @param {string} type - Type d'événement
   * @param {Object} data - Données de l'événement
   */
  function sendLobbyEvent(type, data) {
    for (const ws of wsByUser.values()) sendEvent(ws, type, data);
  }

  // Alias API (compat: ancienne + nouvelle nomenclature)
  const sendRes = sendResponse;
  const sendEvtSocket = sendEvent;
  const sendEvtUser = sendEventToUser;
  const sendEvtLobby = sendLobbyEvent;

  return { 
    // New aliases
    sendRes,
    sendEvtSocket,
    sendEvtUser,
    sendEvtLobby,

    // Legacy names
    sendResponse, 
    sendEvent, 
    sendEventToUser, 
    sendLobbyEvent,

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
 * @param {Function} sendResponse - Fonction sendResponse
 * @param {WebSocket} ws - Client WebSocket
 * @param {Object} req - Requête originale
 * @param {string} code - Code d'erreur
 * @param {string} message - Message d'erreur
 * @param {Object} details - Détails additionnels
 */
export function resError(sendResponse, ws, req, code, message, details) {
   const error = { code, message };
   if (details && typeof details === "object") error.details = details;
   sendResponse(ws, req, false, error);
   return true;
}

export function resBadRequest(sendResponse, ws, req, message = "BAD_REQUEST", details) {
  return resError(sendResponse, ws, req, "BAD_REQUEST", message, details);
}

export function resNotFound(sendResponse, ws, req, message = "NOT_FOUND", details) {
  return resError(sendResponse, ws, req, "NOT_FOUND", message, details);
}

export function resForbidden(sendResponse, ws, req, message = "FORBIDDEN", details) {
  return resError(sendResponse, ws, req, "FORBIDDEN", message, details);
}

export function resBadState(sendResponse, ws, req, message = "BAD_STATE", details) {
  return resError(sendResponse, ws, req, "BAD_STATE", message, details);
}

export function resGameEnd(sendResponse, ws, req, message = "Partie terminée", details) {
  return resError(sendResponse, ws, req, "GAME_END", message, details);
}

export function resNotImplemented(sendResponse, ws, req, message = "Type non géré", details) {
  return resError(sendResponse, ws, req, "NOT_IMPLEMENTED", message, details);
}

export function resServerError(sendResponse, ws, req, message = "Erreur serveur", details) {
  return resError(sendResponse, ws, req, "SERVER_ERROR", message, details);
}
