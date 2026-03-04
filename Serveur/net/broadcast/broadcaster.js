import { ensureGameMeta } from "../../game/meta.js";
import { getSlotStack, slotIdToString } from "../../game/state/slotStore.js";
import { buildTurnPayload } from "../../game/payload/turnPayload.js";

function slotKey(slot_id) {
  return slotIdToString(slot_id);
}

function isTableKey(slotKeyValue) {
  return /^\d+:TABLE:\d+$/.test(String(slotKeyValue ?? ""));
}

function computeSlotSig(game, slot_id) {
  const v = getSlotStack(game, slot_id);
  if (!v || v.length === 0) return "";
  if (Array.isArray(v)) return v.join("|");
  return String(v);
}

function computeTurnSig(game) {
  const t = game.turn;
  if (!t) return "";
  return [
    String(t.current ?? ""),
    String(t.number ?? ""),
    String(t.endsAt ?? ""),
    String(t.durationMs ?? ""),
    String(!!t.paused),
    String(t.remainingMs ?? ""),
  ].join("|");
}

function purgeTableSigs(meta, tableSlots) {
  if (!meta?.slot_sig) return;
  const allowed = new Set((tableSlots || []).map(slotKey));

  for (const k of Object.keys(meta.slot_sig)) {
    if (isTableKey(k) && !allowed.has(k)) {
      delete meta.slot_sig[k];
    }
  }
}

export function createBroadcaster({
  game_id,
  game,
  specs,
  wsByUser,
  sendEvtSocket,
  sendEvtUser,
  emitSlotState,
  gameMeta,
}) {
  const meta = ensureGameMeta(gameMeta, game_id, { initialSent: !!game?.turn });

  const broadcastPartie = (evt, payload) => {
    for (const p of game.players) sendEvtUser(p, evt, payload);
    if (specs && specs.size) for (const s of specs) sendEvtUser(s, evt, payload);
  };

  const pushSlotAll = (slot_id) => {
    const hasSlot = game?.slots instanceof Map && game.slots.has(slot_id);
    if (!hasSlot) return;

    const key = slotKey(slot_id);
    const sig = computeSlotSig(game, slot_id);
    if (meta.slot_sig[key] === sig) return;
    meta.slot_sig[key] = sig;

    emitSlotState(game, game.players, wsByUser, sendEvtSocket, { slot_id, view: "player" });

    if (specs && specs.size) {
      emitSlotState(game, [...specs], wsByUser, sendEvtSocket, { slot_id, view: "spectator" });
    }
  };

  const pushTurnAll = () => {
    const sig = computeTurnSig(game);
    if (meta.turn_sig === sig) return;
    meta.turn_sig = sig;

    const payload = buildTurnPayload(game.turn, { includeEmpty: true });
    broadcastPartie("turn_update", payload);
  };

  const onTableSync = (tableSlots) => {
    purgeTableSigs(meta, tableSlots);
  };

  const sendToUser = (username, evt, payload) => {
    sendEvtUser(username, evt, payload);
  };

  return {
    broadcastPartie,
    sendToUser,
    pushSlotAll,
    pushTurnAll,
    onTableSync,
  };
}
