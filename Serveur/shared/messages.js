// shared/messages.js — constantes POPUP + émetteurs unifiés

// ── Constantes ──────────────────────────────────────────────────────────────

export const POPUP = {
  // Technique
  ERROR: 'POPUP_TECH_ERROR_GENERIC',
  BAD_REQUEST: 'POPUP_TECH_BAD_REQUEST',
  NOT_FOUND: 'POPUP_TECH_NOT_FOUND',
  FORBIDDEN: 'POPUP_TECH_FORBIDDEN',
  BAD_STATE: 'POPUP_TECH_BAD_STATE',
  NOT_IMPLEMENTED: 'POPUP_TECH_NOT_IMPLEMENTED',
  INTERNAL_ERROR: 'POPUP_TECH_INTERNAL_ERROR',
  // Auth
  AUTH_REQUIRED: 'POPUP_AUTH_REQUIRED',
  AUTH_MISSING: 'POPUP_AUTH_MISSING_CREDENTIALS',
  AUTH_ALREADY: 'POPUP_AUTH_ALREADY_CONNECTED',
  AUTH_BAD_PIN: 'POPUP_AUTH_BAD_PIN',
  AUTH_MAX_TRY: 'POPUP_AUTH_MAX_TRY',
  // Invitations
  INVITE_TARGET_INVITED: 'POPUP_INVITE_TARGET_ALREADY_INVITED',
  INVITE_TARGET_INVITING: 'POPUP_INVITE_TARGET_ALREADY_INVITING',
  INVITE_ACTOR_INVITED: 'POPUP_INVITE_ACTOR_ALREADY_INVITED',
  INVITE_ACTOR_INVITING: 'POPUP_INVITE_ACTOR_ALREADY_INVITING',
  INVITE_NOT_FOUND: 'POPUP_INVITE_NOT_FOUND',
  INVITE_DECLINED: 'POPUP_INVITE_DECLINED',
  // Jeu
  GAME_PAUSED: 'POPUP_GAME_PAUSED',
  GAME_ENDED: 'POPUP_GAME_ENDED',
};

// ── Helpers payload ──────────────────────────────────────────────────────────

function firstNonEmpty(...values) {
  for (const value of values) {
    const s = String(value ?? '').trim();
    if (s) {
      return s;
    }
  }
  return '';
}

function safeParams(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return {};
  }
  return value;
}

/** Construit { message_code, [message_params] } */
export function toUiMessage(input = {}, defaults = {}) {
  const src = input && typeof input === 'object' ? input : {};
  const dft = defaults && typeof defaults === 'object' ? defaults : {};

  const out = { message_code: firstNonEmpty(src.message_code, dft.message_code) };
  const params = {
    ...safeParams(dft.message_params),
    ...safeParams(src.message_params),
  };

  if (params && typeof params === 'object' && Object.keys(params).length) {
    out.message_params = params;
  }
  return out;
}

function toArray(to) {
  return Array.isArray(to) ? to : [to];
}

// ── Émetteurs ────────────────────────────────────────────────────────────────

/**
 * Émet show_game_message (codes RULE_* — feedback in-game).
 * Remplace emitGameMessage().
 */
export function emitRule(sendEvtUser, to, code, params) {
  const payload = toUiMessage({ message_code: code, message_params: params });
  for (const u of toArray(to)) {
    if (u) sendEvtUser(u, 'show_game_message', payload);
  }
}

/**
 * Émet un événement métier avec un champ `ui` embarqué.
 * Remplace emitPopupMessage().
 */
export function emitEvt(sendEvtUser, to, event, envelope = {}, code, params) {
  const payload = {
    ...(envelope && typeof envelope === 'object' ? envelope : {}),
    ui: toUiMessage({ message_code: code, message_params: params }),
  };
  for (const u of toArray(to)) {
    if (u) sendEvtUser(u, event, payload);
  }
}
