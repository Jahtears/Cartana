// game/moveRequest.js v2.0 - Thin handler using MoveOrchestrator
import { emitGameEndThenSnapshot } from "../net/broadcast.js";
import { getPlayerGameOrRes, rejectIfSpectatorOrRes, rejectIfEndedOrRes } from "../net/guards.js";
import { resBadRequest, resBadState, resError, resNotFound } from "../net/transport.js";
import { orchestrateMove, MOVE_RESULT_CODE } from "./moveOrchestrator.js";
import { ensureGameMeta } from "./meta.js";
import { GAME_END_REASONS } from "./constants/gameEnd.js";
import { INGAME_MESSAGE } from "./constants/ingameMessages.js";
import { POPUP_MESSAGE } from "../shared/popupMessages.js";

export function handleMoveRequest(ctx, ws, req, data, actor) {
  const {
    sendRes,
    mapSlotFromClientToServer,
    mapSlotForClient,
    getCardById,
    validateMove,
    applyMove,
    isBenchSlot,
    endTurnAfterBenchPlay,
    refillHandIfEmpty,
    hasWonByEmptyDeckSlot,
    getTableSlots,
    processTurnTimeout,
    withGameUpdate,
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
    resBadRequest(sendRes, ws, req, INGAME_MESSAGE.MOVE_INVALID_SLOT, {
      from_slot_id: raw_from,
      to_slot_id: raw_to,
      message_code: INGAME_MESSAGE.MOVE_INVALID_SLOT,
    });
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
    validateMove,
    applyMove,
    getCardById,
    isBenchSlot,
    refillHandIfEmpty,
    hasWonByEmptyDeckSlot,
    getTableSlots,
    endTurnAfterBenchPlay,
    withGameUpdate,
    ctx,
  });

  // ✅ HANDLE RESULT
  if (!orchResult.valid) {
    ctx.trace?.("MOVE_DENIED", {
      actor,
      card_id,
      from_slot_id: String(client_from),
      to_slot_id: String(client_to),
      reason: String(orchResult.reason ?? ""),
    });

    const details = {
      card_id,
      from_slot_id: client_from,
      to_slot_id: client_to,
      message_code: orchResult.reason ?? "",
      message_params: orchResult.reason_params ?? {},
    };

    if (orchResult.code === MOVE_RESULT_CODE.NOT_FOUND) {
      return resNotFound(sendRes, ws, req, orchResult.reason, details);
    }

    if (orchResult.code === MOVE_RESULT_CODE.MOVE_DENIED) {
      return resBadRequest(sendRes, ws, req, orchResult.reason, details);
    }

    return resBadState(sendRes, ws, req, orchResult.reason || INGAME_MESSAGE.MOVE_REJECTED, details);
  }

  // ✅ GAME END: emit end then broadcast
  if (orchResult.winner) {
    emitGameEndThenSnapshot(ctx, game_id, {
      winner: orchResult.winner,
      reason: GAME_END_REASONS.DECK_EMPTY,
      by: actor,
      at: Date.now(),
    });
  }

  // ✅ RESPOND
  sendRes(ws, req, true, orchResult.response);
  return true;
}
