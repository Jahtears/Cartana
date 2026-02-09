// net/broadcast.js v1.1
import { ensureGameMeta } from "../domain/game/meta.js";
import { SlotId } from "../domain/game/SlotManager.js";
import { slotIdToNewString } from "../domain/game/slots.js";

function slotKey(slot_id) {
  if (slot_id instanceof SlotId) return slot_id.toString();
  return String(slot_id ?? "");
}

function isTableKey(key) {
  if (!key) return false;
  // SlotId format: "0:TABLE:1"
  if (key.includes(":TABLE:")) return true;
  return false;
}

function getStackForSig(game, slot_id) {
  if (!game?.slots) return [];

  if (game.slots instanceof Map) {
    const v = game.slots.get(slot_id);
    return Array.isArray(v) ? v : (v ? [v] : []);
  }

  const v = game.slots[slot_id];
  return Array.isArray(v) ? v : (v ? [v] : []);
}

function computeSlotSig(game, slot_id) {
  const v = getStackForSig(game, slot_id);
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
    String(t.remainingMs ?? "")
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
  sendEvent,
  sendEventToUser,
  emitSlotState,
  gameMeta
}) {
  const meta = ensureGameMeta(gameMeta, game_id, { initialSent: !!game?.turn });

  const broadcastPartie = (evt, payload) => {
    for (const p of game.players) sendEventToUser(p, evt, payload);
    if (specs && specs.size) for (const s of specs) sendEventToUser(s, evt, payload);
  };

  const pushSlotAll = (slot_id) => {
    const hasSlot = game?.slots instanceof Map
      ? game.slots.has(slot_id)
      : Object.prototype.hasOwnProperty.call(game.slots || {}, slot_id);

    if (!hasSlot) return;

    const key = slotKey(slot_id);
    const sig = computeSlotSig(game, slot_id);
    if (meta.slot_sig[key] === sig) return;
    meta.slot_sig[key] = sig;

    emitSlotState(game, game.players, wsByUser, sendEvent, { slot_id, view: "player" });

    if (specs && specs.size) {
      emitSlotState(game, [...specs], wsByUser, sendEvent, { slot_id, view: "spectator" });
    }
  };

  // ✅ TURN update dedupé (source de vérité = serveur)
  const pushTurnAll = () => {
    const sig = computeTurnSig(game);
    if (meta.turn_sig === sig) return;
    meta.turn_sig = sig;

    const t = game.turn ?? null;

    broadcastPartie("turn_update", t ? {
      current: t.current,
      turnNumber: t.number,
      endsAt: t.endsAt ?? null,
      durationMs: t.durationMs ?? null,
      paused: !!t.paused,
      remainingMs: Number(t.remainingMs ?? 0),
      serverNow: Date.now()
    } : {
      endsAt: 0,
      durationMs: 0,
      paused: false,
      remainingMs: 0,
      serverNow: Date.now()
    });
  };

  const onTableSync = (tableSlots) => {
    purgeTableSigs(meta, tableSlots);
  };

  const sendToUser = (username, evt, payload) => {
    sendEventToUser(username, evt, payload);
  };

  return {
    broadcastPartie,
    sendToUser,
    pushSlotAll,
    pushTurnAll,
    onTableSync
  };
}

/**
 * Bufferise des emissions "incrémentales" et flush dans un ordre stable :
 *   1) table_sync (si présent) + purge sigs
 *   2) slot_state (dedup géré par broadcaster)
 *   3) turn_update (dedup géré par broadcaster)
 *
 * Objectif: éviter les ordres variables / doublons / envois dispersés.
 */
export function createFlush(bc, trace) {
  const slots = new Set();
  let tableSlots = null;
  let wantTurn = false;
  const messages = [];

  const touch = (slot_id) => {
    if (!slot_id) return;
    slots.add(slot_id);
  };

  const touchMany = (arr) => {
    if (!arr) return;
    for (const s of arr) touch(s);
  };

  const syncTable = (slotsArr) => {
    tableSlots = Array.isArray(slotsArr) ? slotsArr : null;
  };

  const turn = () => { wantTurn = true; };

  const message = (type, data, { to = null } = {}) => {
    if (!type) return;
    messages.push({ type, data: data ?? {}, to });
  };

  const flush = () => {
    if (trace) trace("FLUSH", { table: !!tableSlots, slots: slots.size, turn: !!wantTurn });

    // 1) table_sync
    if (tableSlots) {
      const tablePayload = tableSlots.map(slotIdToNewString);
      bc.broadcastPartie("table_sync", { slots: tablePayload });
      bc.onTableSync(tableSlots);
      tableSlots = null;
    }

    // 2) slots
    for (const s of slots) bc.pushSlotAll(s);
    slots.clear();

    // 3) turn
    if (wantTurn) {
      bc.pushTurnAll();
      wantTurn = false;
    }

    // 4) messages
    if (messages.length) {
      for (const m of messages) {
        if (m.to) {
          const list = Array.isArray(m.to) ? m.to : [m.to];
          for (const u of list) bc.sendToUser(u, m.type, m.data);
        } else {
          bc.broadcastPartie(m.type, m.data);
        }
      }
      messages.length = 0;
    }
  };

  return { touch, touchMany, syncTable, turn, message, flush };
}

/**
 * Ordre canonique de fin de partie:
 *   - game_end (idempotent/once)
 *   - snapshot audience (inject result + reset dedupe)
 */
export function emitGameEndThenSnapshot(ctx, game_id, result, opts) {
  ctx?.trace?.("GAME_END_ONCE", { game_id, winner: result?.winner ?? null, reason: result?.reason ?? "" });
  if (typeof ctx.emitGameEndOnce === "function") {
    ctx.emitGameEndOnce(game_id, result, opts);
  }
  const snapReason = "game_end";
  ctx?.trace?.("SNAPSHOT_AUDIENCE", { game_id, reason: snapReason });
  if (typeof ctx.emitSnapshotsToAudience === "function") {
    ctx.emitSnapshotsToAudience(game_id, { reason: snapReason });
  }
}
