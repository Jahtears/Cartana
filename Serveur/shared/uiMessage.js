import { GAME_MESSAGE, UI_EVENT } from "./constants.js";

function firstNonEmpty(...values) {
  for (const value of values) {
    const s = String(value ?? "").trim();
    if (s) return s;
  }
  return "";
}

function safeMeta(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value;
}

/**
 * Canonicalise un payload UI:
 * - text: texte affiche
 * - code: categorie semantique (couleur/client behavior)
 * - color: fallback legacy optionnel
 * - meta: donnees optionnelles
 */
export function toUiMessage(input = {}, defaults = {}) {
  const src = input && typeof input === "object" ? input : {};
  const dft = defaults && typeof defaults === "object" ? defaults : {};

  const text = firstNonEmpty(src.text, dft.text);
  const code = firstNonEmpty(src.code, dft.code, GAME_MESSAGE.INFO);
  const color = firstNonEmpty(src.color, dft.color);
  const meta = {
    ...safeMeta(dft.meta),
    ...safeMeta(src.meta),
  };

  const out = { text, code };
  if (color) out.color = color;
  if (Object.keys(meta).length > 0) out.meta = meta;
  return out;
}

function normalizeTargets(to) {
  return Array.isArray(to) ? to : [to];
}

/**
 * Emit inline gameplay UI message.
 * - Event: UI_EVENT.GAME_MESSAGE
 * - Payload: normalized UI message
 */
export function emitGameMessage(sendEvtUser, to, input = {}, defaults = {}) {
  if (typeof sendEvtUser !== "function") return false;

  const payload = toUiMessage(input, defaults);
  const targets = normalizeTargets(to);
  let sent = false;

  for (const username of targets) {
    if (!username) continue;
    sendEvtUser(username, UI_EVENT.GAME_MESSAGE, payload);
    sent = true;
  }

  return sent;
}

/**
 * Emit business event with optional popup UI payload.
 * - Event: eventType (business)
 * - Payload: { ...envelope, [field]: normalizedUI }
 */
export function emitPopupMessage(
  sendEvtUser,
  to,
  eventType,
  envelope = {},
  input = {},
  defaults = {},
  field = "ui"
) {
  if (typeof sendEvtUser !== "function") return false;
  if (!eventType || typeof eventType !== "string") return false;

  const ui = toUiMessage(input, defaults);
  const baseEnvelope =
    envelope && typeof envelope === "object" ? envelope : {};
  const payload = { ...baseEnvelope, [field]: ui };

  const targets = normalizeTargets(to);
  let sent = false;

  for (const username of targets) {
    if (!username) continue;
    sendEvtUser(username, eventType, payload);
    sent = true;
  }

  return sent;
}
