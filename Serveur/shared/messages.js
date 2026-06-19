// shared/messages.js — codes wire métier + helpers d'émission

export const ERROR = Object.freeze({
  TECHNICAL_ERROR: 'technical_error',
  BAD_REQUEST: 'bad_request',
  NOT_FOUND: 'not_found',
  FORBIDDEN: 'forbidden',
  BAD_STATE: 'bad_state',
  NOT_IMPLEMENTED: 'not_implemented',
  INTERNAL_ERROR: 'internal_error',
  AUTH_REQUIRED: 'auth_required',
  AUTH_MISSING_CREDENTIALS: 'auth_missing_credentials',
  AUTH_ALREADY_CONNECTED: 'auth_already_connected',
  AUTH_BAD_PIN: 'auth_bad_pin',
  AUTH_RATE_LIMITED: 'auth_rate_limited',
  INVITE_TARGET_ALREADY_INVITED: 'invite_target_already_invited',
  INVITE_TARGET_ALREADY_INVITING: 'invite_target_already_inviting',
  INVITE_ACTOR_ALREADY_INVITED: 'invite_actor_already_invited',
  INVITE_ACTOR_ALREADY_INVITING: 'invite_actor_already_inviting',
  INVITE_NOT_FOUND: 'invite_not_found',
  GAME_PAUSED: 'game_paused',
  GAME_ENDED: 'game_ended',
  INVALID_CLIENT_SLOT: 'invalid_client_slot',
  MOVE_DENIED: 'move_denied',
  DECK_TO_TABLE_ONLY: 'deck_to_table_only',
  NOT_YOUR_TURN: 'not_your_turn',
  BENCH_TO_TABLE_ONLY: 'bench_to_table_only',
  ACE_ON_DECK: 'ace_on_deck',
  ACE_IN_HAND: 'ace_in_hand',
  ALLOWED_ON_TABLE_ONLY: 'allowed_on_table_only',
  OPPONENT_SLOT_FORBIDDEN: 'opponent_slot_forbidden',
  TURN_TIMEOUT: 'turn_timeout',
});

export const FEEDBACK = Object.freeze({
  OK: 'ok',
  TURN_START_FIRST: 'turn_start_first',
  TURN_START: 'turn_start',
  TURN_TIMEOUT: 'turn_timeout',
  MOVE_DENIED: 'move_denied',
  DECK_TO_TABLE_ONLY: 'deck_to_table_only',
  NOT_YOUR_TURN: 'not_your_turn',
  BENCH_TO_TABLE_ONLY: 'bench_to_table_only',
  ACE_ON_DECK: 'ace_on_deck',
  ACE_IN_HAND: 'ace_in_hand',
  ALLOWED_ON_TABLE_ONLY: 'allowed_on_table_only',
  OPPONENT_SLOT_FORBIDDEN: 'opponent_slot_forbidden',
});

export const GAME_FEEDBACK_EVENT = 'game_feedback';

const FEEDBACK_CODE_BY_RULE = Object.freeze({
  RULE_OK: FEEDBACK.OK,
  RULE_TURN_START_FIRST: FEEDBACK.TURN_START_FIRST,
  RULE_TURN_START: FEEDBACK.TURN_START,
  RULE_TURN_TIMEOUT: FEEDBACK.TURN_TIMEOUT,
  RULE_MOVE_DENIED: FEEDBACK.MOVE_DENIED,
  RULE_DECK_TO_TABLE: FEEDBACK.DECK_TO_TABLE_ONLY,
  RULE_NOT_YOUR_TURN: FEEDBACK.NOT_YOUR_TURN,
  RULE_BENCH_TO_TABLE: FEEDBACK.BENCH_TO_TABLE_ONLY,
  RULE_ACE_ON_DECK: FEEDBACK.ACE_ON_DECK,
  RULE_ACE_IN_HAND: FEEDBACK.ACE_IN_HAND,
  RULE_ALLOWED_ON_TABLE: FEEDBACK.ALLOWED_ON_TABLE_ONLY,
  RULE_OPPONENT_SLOT_FORBIDDEN: FEEDBACK.OPPONENT_SLOT_FORBIDDEN,
});

const ERROR_CODE_BY_RULE = Object.freeze({
  RULE_TURN_TIMEOUT: ERROR.TURN_TIMEOUT,
  RULE_MOVE_DENIED: ERROR.MOVE_DENIED,
  RULE_DECK_TO_TABLE: ERROR.DECK_TO_TABLE_ONLY,
  RULE_NOT_YOUR_TURN: ERROR.NOT_YOUR_TURN,
  RULE_BENCH_TO_TABLE: ERROR.BENCH_TO_TABLE_ONLY,
  RULE_ACE_ON_DECK: ERROR.ACE_ON_DECK,
  RULE_ACE_IN_HAND: ERROR.ACE_IN_HAND,
  RULE_ALLOWED_ON_TABLE: ERROR.ALLOWED_ON_TABLE_ONLY,
  RULE_OPPONENT_SLOT_FORBIDDEN: ERROR.OPPONENT_SLOT_FORBIDDEN,
});

const WIRE_CODE_PATTERN = /^[a-z0-9]+(?:_[a-z0-9]+)*$/;

function safeParams(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return {};
  }
  return value;
}

function normalizeWireCode(raw, fallback) {
  const candidate = String(raw ?? '').trim();
  if (WIRE_CODE_PATTERN.test(candidate)) {
    return candidate;
  }
  return fallback;
}

function toArray(value) {
  return Array.isArray(value) ? value : [value];
}

export function toErrorCode(raw, fallback = ERROR.TECHNICAL_ERROR) {
  const candidate = String(raw ?? '').trim();
  return normalizeWireCode(ERROR_CODE_BY_RULE[candidate] ?? candidate, fallback);
}

export function toFeedbackCode(raw, fallback = FEEDBACK.MOVE_DENIED) {
  const candidate = String(raw ?? '').trim();
  return normalizeWireCode(FEEDBACK_CODE_BY_RULE[candidate] ?? candidate, fallback);
}

export function normalizeFeedbackPayload(input = {}) {
  const src = input && typeof input === "object" ? input : {};
  const out = { code: toFeedbackCode(src.code, FEEDBACK.MOVE_DENIED) };
  const params = safeParams(src.params);
  if (Object.keys(params).length > 0) {
    out.params = params;
  }
  return out;
}

export function emitFeedback(sendEvtUser, to, code, params) {
  const payload = normalizeFeedbackPayload({ code, params });
  for (const username of toArray(to)) {
    if (username) {
      sendEvtUser(username, GAME_FEEDBACK_EVENT, payload);
    }
  }
}

export function emitEvent(sendEvtUser, to, event, envelope = {}) {
  const payload = envelope && typeof envelope === 'object' ? envelope : {};
  for (const username of toArray(to)) {
    if (username) {
      sendEvtUser(username, event, payload);
    }
  }
}
