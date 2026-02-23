// game/moveRequest.js v2.0 - Thin handler using MoveOrchestrator
import { emitGameEndThenSnapshot } from "../net/broadcast.js";
import { getPlayerGameOrRes, rejectIfSpectatorOrRes, rejectIfEndedOrRes } from "../net/guards.js";
import { resError } from "../net/transport.js";
import { orchestrateMove } from "./moveOrchestrator.js";
import { ensureGameMeta } from "./meta.js";
import { GAME_END_REASONS } from "./constants/gameEnd.js";
import { INGAME_MESSAGE } from "./constants/ingameMessages.js";
import { POPUP_MESSAGE } from "../shared/popupMessages.js";

function safeObject(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value;
}

const INGAME_MESSAGE_CODES = new Set(Object.values(INGAME_MESSAGE));

function buildMoveDetails(cardId, fromSlotId) {
  const details = {};
  const normalizedCardId = String(cardId ?? "").trim();
  const normalizedFromSlotId = String(fromSlotId ?? "").trim();

  if (normalizedCardId) details.card_id = normalizedCardId;
  if (normalizedFromSlotId) details.from_slot_id = normalizedFromSlotId;
  return details;
}

function buildMoveClientErrorPayload({ moveError, cardId, fromSlotId }) {
  const kind = String(moveError?.kind ?? "").trim();
  const payload = {
    message_code: INGAME_MESSAGE.MOVE_DENIED,
  };

  if (kind === "user") {
    const userCode = String(moveError?.code ?? "").trim();
    if (INGAME_MESSAGE_CODES.has(userCode)) {
      payload.message_code = userCode;
    }

    const params = safeObject(moveError?.params);
    if (Object.keys(params).length > 0) {
      payload.message_params = params;
    }
  }

  const details = buildMoveDetails(cardId, fromSlotId);
  if (Object.keys(details).length > 0) payload.details = details;

  return payload;
}

function deniedTracePayload(moveError) {
  const kind = String(moveError?.kind ?? "").trim();
  if (kind === "user") {
    return {
      reason_code: String(moveError?.code ?? ""),
    };
  }

  return {
    reason_debug: String(moveError?.debug_reason ?? "unknown"),
  };
}

export function handleMoveRequest(ctx, ws, req, data, actor) {
  const {
    sendRes,
    mapSlotFromClientToServer,
    mapSlotForClient,
    processTurnTimeout,
  } = ctx;

  // ✅ GUARDS: game, player, spectator, ended
  const pg = getPlayerGameOrRes(ctx, ws, req, actor);
  if (!pg) return true;
  const { game_id, game } = pg;
  ensureGameMeta(ctx.state.gameMeta, game_id, { initialSent: !!game?.turn });

  if (rejectIfSpectatorOrRes(ctx, ws, req, game_id, actor, POPUP_MESSAGE.TECH_FORBIDDEN)) return true;
  if (rejectIfEndedOrRes(ctx, ws, req, game_id, game)) return true;
  if (game?.turn?.paused) {
    return resError(sendRes, ws, req, POPUP_MESSAGE.GAME_PAUSED, { game_id });
  }

  // ✅ TURN EXPIRY CHECK
  if (typeof processTurnTimeout === "function") {
    const didExpire = processTurnTimeout(game_id);
    if (didExpire && String(game?.turn?.current ?? "") !== actor) {
      return resError(sendRes, ws, req, INGAME_MESSAGE.TURN_TIMEOUT, { game_id });
    }
  }

  // ✅ EXTRACT & MAP SLOTS
  const card_id = String(data.card_id ?? "").trim();
  const raw_from = String(data.from_slot_id ?? "").trim();
  const raw_to = String(data.to_slot_id ?? "").trim();

  const from_slot_id = mapSlotFromClientToServer(raw_from, actor, game);
  const to_slot_id = mapSlotFromClientToServer(raw_to, actor, game);

  ctx.trace?.("MOVE_REQ", {
    actor,
    card_id,
    raw_from,
    raw_to,
    from_slot_id: from_slot_id ? String(from_slot_id) : null,
    to_slot_id: to_slot_id ? String(to_slot_id) : null,
    turn_current: String(game?.turn?.current ?? ""),
    turn_number: Number(game?.turn?.number ?? 0),
  });

  if (!from_slot_id || !to_slot_id) {
    const moveError = {
      valid: false,
      kind: "technical",
      debug_reason: "invalid_client_slot",
    };
    const errorPayload = buildMoveClientErrorPayload({
      moveError,
      cardId: card_id,
      fromSlotId: raw_from,
    });

    ctx.trace?.("MOVE_DENIED", {
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

  const client_from = mapSlotForClient(from_slot_id, actor, game);
  const client_to = mapSlotForClient(to_slot_id, actor, game);

  // ✅ ORCHESTRATE: validate → apply → refill → track → check win
  const orchResult = orchestrateMove({
    game_id,
    game,
    actor,
    card_id,
    from_slot_id,
    to_slot_id,
    ctx,
  });

  // ✅ HANDLE RESULT
  if (!orchResult.valid) {
    const errorPayload = buildMoveClientErrorPayload({
      moveError: orchResult,
      cardId: card_id,
      fromSlotId: client_from,
    });

    ctx.trace?.("MOVE_DENIED", {
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

  // ✅ GAME END: emit end then broadcast
  if (orchResult.winner || orchResult.game_end_reason) {
    emitGameEndThenSnapshot(ctx, game_id, {
      winner: orchResult.winner,
      reason: orchResult.game_end_reason || GAME_END_REASONS.DECK_EMPTY,
      by: actor,
      at: Date.now(),
    });
  }

  // ✅ RESPOND
  sendRes(ws, req, true, orchResult.response);
  return true;
}
