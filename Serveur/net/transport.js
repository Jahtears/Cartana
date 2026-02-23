// net/transport.js v3.0 - Transport et réponses
// Le heartbeat est maintenant centralisé dans heartbeat.js
import { POPUP_MESSAGE } from "../shared/popupMessages.js";

/**
 * Vérifier si un WebSocket est ouvert
 */
function wsIsOpen(ws) {
  return !!ws && ws.readyState === 1;
}

function safeObject(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value;
}

function normalizeMessageCode(raw, fallback = POPUP_MESSAGE.TECH_ERROR_GENERIC) {
  const candidate = String(raw ?? "").trim();
  if (!candidate) return fallback;
  if (candidate.startsWith("POPUP_") || candidate.startsWith("INGAME_")) {
    return candidate;
  }
  return fallback;
}

function normalizeErrorPayload(payload) {
  const src = safeObject(payload);
  const details = safeObject(src.details);

  const message_code = normalizeMessageCode(src.message_code, POPUP_MESSAGE.TECH_ERROR_GENERIC);

  const message_params = {
    ...safeObject(details.message_params),
    ...safeObject(src.message_params),
  };

  const out = {
    message_code,
  };

  if (Object.keys(message_params).length > 0) out.message_params = message_params;
  if (Object.keys(details).length > 0) out.details = details;
  return out;
}

/**
 * Envoyer un message brut de manière sûre
 * @param {WebSocket} ws - Client WebSocket
 * @param {Object} envelope - Enveloppe de message
 * @param {Function} onSend - Callback appelé si envoi réussi
 * @returns {boolean} true si envoyé, false sinon
 */
function safeSend(ws, envelope, onSend) {
  if (!wsIsOpen(ws)) return false;
  try {
    ws.send(JSON.stringify(envelope));
    if (typeof onSend === "function") onSend(envelope);
    return true;
  } catch {
    return false;
  }
}

/**
 * Créer le transport (fonctions d'envoi)
 * @param {Object} config - {wsByUser, onSend?}
 * @returns {Object} Transport avec API V2
 */
export function createTransport({ wsByUser, onSend }) {
  /**
   * Envoyer une réponse à une requête
   * @param {WebSocket} ws - Client WebSocket
   * @param {Object} req - Requête originale
   * @param {boolean} ok - Succès/Erreur
   * @param {Object} payload - Données ou erreur
   */
  function sendRes(ws, req, ok, payload) {
    const base = { kind: "res", type: req.type, rid: req.rid, ok: !!ok };
    if (ok) return safeSend(ws, { ...base, data: payload ?? {} }, onSend);
    const error = normalizeErrorPayload(payload);
    return safeSend(ws, {
      ...base,
      error,
    }, onSend);
  }

  /**
   * Envoyer un événement à un client
   * @param {WebSocket} ws - Client WebSocket
   * @param {string} type - Type d'événement
   * @param {Object} data - Données de l'événement
   */
  function sendEvtSocket(ws, type, data) {
    return safeSend(ws, { kind: "evt", type, data: data ?? {} }, onSend);
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
   Conventions: retournent true (pratique: `return resError(...)`)
-------------------------------------------------------- */

/**
 * Envoyer une erreur
 * @param {Function} sendRes - Fonction sendRes
 * @param {WebSocket} ws - Client WebSocket
 * @param {Object} req - Requête originale
 * @param {string} message_code - Code de message UI (POPUP_* / INGAME_*)
 * @param {Object} details - Détails additionnels
 */
export function resError(sendRes, ws, req, message_code, details) {
  const error = { message_code };
  if (details && typeof details === "object") error.details = details;
  sendRes(ws, req, false, error);
  return true;
}
