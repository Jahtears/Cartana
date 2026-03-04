import { GAME_END_REASONS } from "../constants/gameEnd.js";
import { SLOT_TYPES } from "../constants/slots.js";
import { mapSlotForClient } from "../boundary/slotIdMapper.js";
import { buildCardPayload } from "./cardPayload.js";
import { getTableSlots } from "../helpers/tableHelper.js";
import {
  getSlotCount,
  getSlotStack,
  isOwnerForSlot,
  slotIdToString,
} from "../state/slotStore.js";
import {
  applySlotDragPolicy,
  getVisibleCardIdsForSlot,
  toSlotStack,
} from "../helpers/slotViewHelpers.js";
import { getCardById } from "../state/cardStore.js";
import { buildTurnPayload } from "./turnPayload.js";

function buildSlotStatePayload(game, username, slotId, view, { forceDisableDrag = false } = {}) {
  const disableDrag = view === "spectator" || !!forceDisableDrag;

  const clientSlot = slotIdToString(
    view === "spectator" ? slotId : mapSlotForClient(slotId, username, game)
  );

  const owner = view === "spectator"
    ? false
    : isOwnerForSlot(game, slotId, username);

  const cards = [];
  const stack = toSlotStack(getSlotStack(game, slotId));
  const count = getSlotCount(game, slotId);

  if (!stack.length) return { slot_id: clientSlot, cards, count };

  const slotType = slotId?.type ?? null;
  const ids = getVisibleCardIdsForSlot(slotType, stack);

  for (let i = 0; i < ids.length; i++) {
    const card = getCardById(game, ids[i]);
    if (!card) continue;

    const isDeckSecondFromTop = slotType === SLOT_TYPES.DECK
      && stack.length >= 2
      && ids[i] === stack[stack.length - 2];
    const payload = buildCardPayload(
      card,
      slotId,
      owner,
      disableDrag,
      clientSlot,
      isDeckSecondFromTop
    );
    payload.draggable = applySlotDragPolicy(slotType, stack, ids[i], payload.draggable);
    cards.push(payload);
  }

  return { slot_id: clientSlot, cards, count };
}

function buildStateSnapshotPayload(game, username, view, { result = null, forceDisableDrag = false } = {}) {
  const tableSlotIds = getTableSlots(game);

  const table = tableSlotIds.map((slotId) =>
    slotIdToString(view === "spectator" ? slotId : mapSlotForClient(slotId, username, game))
  );

  const slots = {};
  const slot_counts = {};

  const allSlots = game?.slots instanceof Map ? Array.from(game.slots.keys()) : [];
  const nonTable = allSlots.filter((s) => s?.type !== SLOT_TYPES.TABLE);

  for (const slotId of nonTable) {
    const { slot_id: clientSlot, cards, count } = buildSlotStatePayload(game, username, slotId, view, { forceDisableDrag });
    slots[clientSlot] = cards;
    slot_counts[clientSlot] = count;
  }

  for (const slotId of tableSlotIds) {
    const { slot_id: clientSlot, cards, count } = buildSlotStatePayload(game, username, slotId, view, { forceDisableDrag });
    slots[clientSlot] = cards;
    slot_counts[clientSlot] = count;
  }

  const turn = buildTurnPayload(game.turn, { includeEmpty: false });

  return {
    view,
    table,
    slots,
    slot_counts,
    turn,
    result,
  };
}

function publicGameEndResult(result) {
  if (!result || typeof result !== "object") {
    return {
      winner: null,
      reason: GAME_END_REASONS.ABANDON,
      by: "",
      at: 0,
    };
  }

  const winner =
    typeof result.winner === "string" && result.winner.trim()
      ? result.winner
      : null;
  const rawReason = String(result.reason ?? "").trim().toLowerCase();
  const reason = rawReason === GAME_END_REASONS.ABANDON
    || rawReason === GAME_END_REASONS.DECK_EMPTY
    || rawReason === GAME_END_REASONS.PILE_EMPTY
    || rawReason === GAME_END_REASONS.TIMEOUT_STREAK
    ? rawReason
    : GAME_END_REASONS.ABANDON;
  const by = typeof result.by === "string" ? result.by : "";
  const at = typeof result.at === "number" && Number.isFinite(result.at) ? result.at : 0;

  return { winner, reason, by, at };
}

export {
  buildSlotStatePayload,
  buildStateSnapshotPayload,
  publicGameEndResult,
};
