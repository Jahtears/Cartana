import { emitGameEndThenSnapshot } from '../../net/broadcast/gameEndBroadcast.js';
import {
  getPlayerGameOrRes,
  rejectIfSpectatorOrRes,
  rejectIfEndedOrRes,
} from '../../net/guards.js';
import { resError } from '../../net/transport.js';
import { orchestrateMove } from '../../game/usecases/move/orchestrateMove.js';
import { ensureGameMeta } from '../../game/meta.js';
import { GAME_END_REASONS } from '../../game/constants/gameEnd.js';
import { POPUP_MESSAGE } from '../../shared/popupMessages.js';
import { deniedTracePayload, technicalDenied } from '../../game/helpers/deniedHelpers.js';
import { mapSlotForClient, mapSlotFromClientToServer } from '../../game/boundary/slotIdMapper.js';

function safeObject(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return {};
  }
  return value;
}

const RULE_CODES = new Set([
  'RULE_OK',
  'RULE_MOVE_DENIED',
  'RULE_DECK_TO_TABLE',
  'RULE_NOT_YOUR_TURN',
  'RULE_BENCH_TO_TABLE',
  'RULE_ACE_ON_DECK',
  'RULE_ACE_IN_HAND',
  'RULE_ALLOWED_ON_TABLE',
  'RULE_OPPONENT_SLOT_FORBIDDEN',
  'RULE_TURN_START_FIRST',
  'RULE_TURN_START',
  'RULE_TURN_TIMEOUT',
]);

function buildMoveDetails(cardId, fromSlotId) {
  const details = {};
  const normalizedCardId = String(cardId ?? '').trim();
  const normalizedFromSlotId = String(fromSlotId ?? '').trim();

  if (normalizedCardId) {
    details.card_id = normalizedCardId;
  }
  if (normalizedFromSlotId) {
    details.from_slot_id = normalizedFromSlotId;
  }
  return details;
}

function buildMoveClientErrorPayload({ moveError, cardId, fromSlotId }) {
  const kind = String(moveError?.kind ?? '').trim();
  const payload = {
    message_code: 'RULE_MOVE_DENIED',
  };

  if (kind === 'user') {
    const userCode = String(moveError?.code ?? '').trim();
    if (RULE_CODES.has(userCode)) {
      payload.message_code = userCode;
    }

    const params = safeObject(moveError?.params);
    if (Object.keys(params).length > 0) {
      payload.message_params = params;
    }
  }

  const details = buildMoveDetails(cardId, fromSlotId);
  if (Object.keys(details).length > 0) {
    payload.details = details;
  }

  return payload;
}

export function handleMoveRequest(ctx, ws, req, data, actor) {
  const sendRes = ctx.sendRes;
  const turnUsecases = ctx.usecases?.turn ?? ctx;
  const boundarySlot = ctx.boundary?.slot ?? {};
  const mapFromClient =
    boundarySlot.mapSlotFromClientToServer ??
    ctx.mapSlotFromClientToServer ??
    mapSlotFromClientToServer;
  const mapForClient = boundarySlot.mapSlotForClient ?? ctx.mapSlotForClient ?? mapSlotForClient;
  const processTurnTimeout = turnUsecases.processTurnTimeout;

  //  GUARDS: game, player, spectator, ended
  const pg = getPlayerGameOrRes(ctx, ws, req, actor);
  if (!pg) {
    return true;
  }
  const { game_id, game } = pg;
  ensureGameMeta(ctx.state.gameMeta, game_id, { initialSent: Boolean(game?.turn) });

  if (rejectIfSpectatorOrRes(ctx, ws, req, game_id, actor, POPUP_MESSAGE.TECH_FORBIDDEN)) {
    return true;
  }
  if (rejectIfEndedOrRes(ctx, ws, req, game_id, game)) {
    return true;
  }
  if (game?.turn?.paused) {
    return resError(sendRes, ws, req, POPUP_MESSAGE.GAME_PAUSED, { game_id });
  }

  //  TURN EXPIRY CHECK
  if (typeof processTurnTimeout === 'function') {
    const didExpire = processTurnTimeout(game_id);
    if (didExpire && String(game?.turn?.current ?? '') !== actor) {
      return resError(sendRes, ws, req, 'RULE_TURN_TIMEOUT', { game_id });
    }
  }

  //  EXTRACT & MAP SLOTS
  const card_id = String(data.card_id ?? '').trim();
  const raw_from = String(data.from_slot_id ?? '').trim();
  const raw_to = String(data.to_slot_id ?? '').trim();

  const from_slot_id = mapFromClient(raw_from, actor, game);
  const to_slot_id = mapFromClient(raw_to, actor, game);

  ctx.trace?.('MOVE_REQ', {
    actor,
    card_id,
    raw_from,
    raw_to,
    from_slot_id: from_slot_id ? String(from_slot_id) : null,
    to_slot_id: to_slot_id ? String(to_slot_id) : null,
    turn_current: String(game?.turn?.current ?? ''),
    turn_number: Number(game?.turn?.number ?? 0),
  });

  if (!from_slot_id || !to_slot_id) {
    const moveError = technicalDenied('invalid_client_slot');
    const errorPayload = buildMoveClientErrorPayload({
      moveError,
      cardId: card_id,
      fromSlotId: raw_from,
    });

    ctx.trace?.('RULE_MOVE_DENIED', {
      actor,
      card_id,
      from_slot_id: raw_from || null,
      to_slot_id: raw_to || null,
      ...deniedTracePayload(moveError),
      reason_client: errorPayload.message_code,
    });

    sendRes(ws, req, false, errorPayload);
    return true;
  }

  const client_from = mapForClient(from_slot_id, actor, game);
  const client_to = mapForClient(to_slot_id, actor, game);

  //  ORCHESTRATE: validate → apply → refill → track → check win
  const orchResult = orchestrateMove({
    game_id,
    game,
    actor,
    card_id,
    from_slot_id,
    to_slot_id,
    ctx,
  });

  //  HANDLE RESULT
  if (!orchResult.valid) {
    const errorPayload = buildMoveClientErrorPayload({
      moveError: orchResult,
      cardId: card_id,
      fromSlotId: client_from,
    });

    ctx.trace?.('RULE_MOVE_DENIED', {
      actor,
      card_id,
      from_slot_id: String(client_from),
      to_slot_id: String(client_to),
      ...deniedTracePayload(orchResult),
      reason_client: errorPayload.message_code,
    });

    sendRes(ws, req, false, errorPayload);
    return true;
  }

  //  GAME END: emit end then broadcast
  if (orchResult.winner || orchResult.game_end_reason) {
    emitGameEndThenSnapshot(ctx, game_id, {
      winner: orchResult.winner,
      reason: orchResult.game_end_reason || GAME_END_REASONS.DECK_EMPTY,
      by: actor,
      at: Date.now(),
    });
  }

  //  RESPOND
  sendRes(ws, req, true, orchResult.response);
  return true;
}
