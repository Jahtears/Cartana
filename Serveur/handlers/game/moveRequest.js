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
import { ERROR, toErrorCode } from '../../shared/messages.js';
import { mapSlotForClient, mapSlotFromClientToServer } from '../../game/boundary/slotIdMapper.js';

// ── Helpers inline ──────────────────────────────────────────────────────────

const tech = (reason) => ({ valid: false, kind: 'technical', debug_reason: reason });

function buildErrorPayload(moveError, cardId, fromSlotId) {
  let code = ERROR.TECHNICAL_ERROR;
  if (moveError?.kind === 'user') {
    code = toErrorCode(moveError.code, ERROR.MOVE_DENIED);
  } else if (String(moveError?.debug_reason ?? '').trim() === ERROR.INVALID_CLIENT_SLOT) {
    code = ERROR.INVALID_CLIENT_SLOT;
  }

  const payload = { code };
  if (moveError?.kind === 'user' && moveError.params) payload.params = moveError.params;

  const details = {};
  if (cardId) details.card_id = String(cardId);
  if (fromSlotId) details.from_slot_id = String(fromSlotId);
  if (Object.keys(details).length) payload.details = details;

  return payload;
}

// ── Handler ──────────────────────────────────────────────────────────────────

export function handleMoveRequest(ctx, ws, req, data, actor) {
  const { sendRes } = ctx;
  const turnUsecases = ctx.usecases?.turn ?? ctx;
  const boundary = ctx.boundary?.slot ?? {};
  const mapFromClient = boundary.mapSlotFromClientToServer ?? mapSlotFromClientToServer;
  const mapForClient = boundary.mapSlotForClient ?? mapSlotForClient;
  const processTurnTimeout = turnUsecases.processTurnTimeout;

  const pg = getPlayerGameOrRes(ctx, ws, req, actor);
  if (!pg) return true;
  const { game_id, game } = pg;

  ensureGameMeta(ctx.state.gameMeta, game_id, { initialSent: Boolean(game?.turn) });

  if (rejectIfSpectatorOrRes(ctx, ws, req, game_id, actor, ERROR.FORBIDDEN)) return true;
  if (rejectIfEndedOrRes(ctx, ws, req, game_id, game)) return true;
  if (game?.turn?.paused) return resError(sendRes, ws, req, ERROR.GAME_PAUSED, { game_id });

  if (typeof processTurnTimeout === 'function') {
    const expired = processTurnTimeout(game_id);
    if (expired && String(game?.turn?.current ?? '') !== actor)
      return resError(sendRes, ws, req, ERROR.TURN_TIMEOUT, { game_id });
  }

  const card_id = String(data.card_id ?? '').trim();
  const raw_from = String(data.from_slot_id ?? '').trim();
  const raw_to = String(data.to_slot_id ?? '').trim();

  const from_slot_id = mapFromClient(raw_from, actor, game);
  const to_slot_id = mapFromClient(raw_to, actor, game);

  if (!from_slot_id || !to_slot_id) {
    sendRes(ws, req, false, buildErrorPayload(tech(ERROR.INVALID_CLIENT_SLOT), card_id, raw_from));
    return true;
  }

  const client_from = mapForClient(from_slot_id, actor, game);

  const result = orchestrateMove({ game_id, game, actor, card_id, from_slot_id, to_slot_id, ctx });

  if (!result.valid) {
    sendRes(ws, req, false, buildErrorPayload(result, card_id, client_from));
    return true;
  }

  if (result.winner !== undefined || result.game_end_reason) {
    emitGameEndThenSnapshot(ctx, game_id, {
      winner: result.winner,
      reason: result.game_end_reason || GAME_END_REASONS.DECK_EMPTY,
      by: actor,
      at: Date.now(),
    });
  }

  sendRes(ws, req, true, result.response);
  return true;
}
