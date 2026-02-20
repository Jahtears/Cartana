const GAME_MESSAGE_EVENT = "show_game_message";

function firstNonEmpty(...values) {
  for (const value of values) {
    const s = String(value ?? "").trim();
    if (s) return s;
  }
  return "";
}

function safeParams(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value;
}

/**
 * Canonicalise un payload UI strict:
 * - message_code: code POPUP_* ou INGAME_*
 * - message_params: paramètres de template optionnels
 */
export function toUiMessage(input = {}, defaults = {}) {
  const src = input && typeof input === "object" ? input : {};
  const dft = defaults && typeof defaults === "object" ? defaults : {};

  const message_code = firstNonEmpty(src.message_code, dft.message_code);

  const message_params = {
    ...safeParams(dft.message_params),
    ...safeParams(src.message_params),
  };

  const out = { message_code };
  if (Object.keys(message_params).length > 0) out.message_params = message_params;
  return out;
}

function normalizeTargets(to) {
  return Array.isArray(to) ? to : [to];
}

/**
 * Emit ingame gameplay UI message.
 * - Event: show_game_message
 * - Payload: { message_code, message_params? }
 */
export function emitGameMessage(sendEvtUser, to, input = {}, defaults = {}) {
  if (typeof sendEvtUser !== "function") return false;

  const payload = toUiMessage(input, defaults);
  const targets = normalizeTargets(to);
  let sent = false;

  for (const username of targets) {
    if (!username) continue;
    sendEvtUser(username, GAME_MESSAGE_EVENT, payload);
    sent = true;
  }

  return sent;
}

/**
 * Emit business event with optional popup UI payload.
 * - Event: eventType (business)
 * - Payload: { ...envelope, [field]: { message_code, message_params? } }
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
