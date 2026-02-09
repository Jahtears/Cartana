// handlers/moveRequest.js v2.0 - Thin handler using MoveOrchestrator
import { emitGameEndThenSnapshot } from "../../net/broadcast.js";
import { getPlayerGameOrRes, rejectIfSpectatorOrRes, rejectIfEndedOrRes } from "../../net/guards.js";
import { resBadRequest, resNotFound } from "../../net/transport.js";
import { orchestrateMove } from "../../domain/game/moveOrchestrator.js";
import { ensureGameMeta } from "../../domain/game/meta.js";

export function handleMoveRequest(ctx, ws, req, data, actor) {
  const {
    sendResponse,
    mapSlotFromClientToServer,
    mapSlotForClient,
    findCardById,
    validateMove,
    applyMove,
    isBenchSlot,
    endTurnAfterBenchPlay,
    refillHandIfEmpty,
    hasWonByEmptyDeckSlot,
    getTableSlots,
    emitSnapshotsToAudience,
    expireTurnIfNeeded,
    withGameUpdate,
  } = ctx;

  // ✅ GUARDS: game, player, spectator, ended
  const pg = getPlayerGameOrRes(ctx, ws, req, actor);
  if (!pg) return true;
  const { game_id, game } = pg;
  const meta = ensureGameMeta(ctx.state.gameMeta, game_id, { initialSent: !!game?.turn });

  if (rejectIfSpectatorOrRes(ctx, ws, req, game_id, actor, "Spectateur: déplacement interdit")) return true;
  if (rejectIfEndedOrRes(ctx, ws, req, game_id, game)) return true;
  if (meta.pause?.active) {
    sendResponse(ws, req, false, { code: "GAME_PAUSED", message: "Partie en pause: adversaire déconnecté" });
    return true;
  }

  // ✅ TURN EXPIRY CHECK
  if (typeof expireTurnIfNeeded === "function") {
    const didExpire = expireTurnIfNeeded(game_id);
    if (didExpire && String(game?.turn?.current ?? "") !== actor) {
      sendResponse(ws, req, false, { code: "TURN_TIMEOUT", message: "Temps écoulé" });
      return true;
    }
  }

  // ✅ EXTRACT & MAP SLOTS
  const card_id = String(data.card_id ?? "").trim();
  const raw_from = String(data.from_slot_id ?? "").trim();
  const raw_to = String(data.to_slot_id ?? "").trim();

  const from_slot_id = mapSlotFromClientToServer(raw_from, actor, game);
  const to_slot_id = mapSlotFromClientToServer(raw_to, actor, game);

  if (!from_slot_id || !to_slot_id) {
    resBadRequest(sendResponse, ws, req, "slot_id invalide", {
      from_slot_id: raw_from,
      to_slot_id: raw_to,
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
    findCardById,
    isBenchSlot,
    refillHandIfEmpty,
    hasWonByEmptyDeckSlot,
    getTableSlots,
    endTurnAfterBenchPlay,
    withGameUpdate,
    emitSnapshotsToAudience,
    ctx,
  });

  // ✅ HANDLE RESULT
  if (!orchResult.valid) {
    const details = { card_id, from_slot_id: client_from, to_slot_id: client_to };
    return resNotFound(sendResponse, ws, req, orchResult.reason, details);
  }

  // ✅ GAME END: emit end then broadcast
  if (orchResult.winner) {
    emitGameEndThenSnapshot(ctx, game_id, {
      winner: orchResult.winner,
      reason: "deck_empty",
      by: actor,
      at: Date.now(),
    });
  }

  // ✅ RESPOND
  sendResponse(ws, req, true, orchResult.response);
  return true;
}
