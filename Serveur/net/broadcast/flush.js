import { slotIdToString } from '../../game/state/slotStore.js';
import { toUiMessage } from '../../shared/uiMessage.js';

const GAME_MESSAGE_EVENT = 'show_game_message';

export function createFlush(bc, trace) {
  const slots = new Set();
  let tableSlots = null;
  let wantTurn = false;
  const messages = [];

  const touch = (slot_id) => {
    if (!slot_id) {
      return;
    }
    slots.add(slot_id);
  };

  const touchMany = (arr) => {
    if (!arr) {
      return;
    }
    for (const s of arr) {
      touch(s);
    }
  };

  const syncTable = (slotsArr) => {
    tableSlots = Array.isArray(slotsArr) ? slotsArr : null;
  };

  const turn = () => {
    wantTurn = true;
  };

  const message = (type, data, { to = null } = {}) => {
    if (!type) {
      return;
    }
    const payload = type === GAME_MESSAGE_EVENT ? toUiMessage(data ?? {}) : (data ?? {});
    messages.push({ type, data: payload, to });
  };

  const flush = () => {
    if (trace) {
      trace('FLUSH', {
        table: Boolean(tableSlots),
        table_slots: tableSlots ? tableSlots.map(slotIdToString) : [],
        slots: slots.size,
        turn: Boolean(wantTurn),
      });
    }

    if (tableSlots) {
      const tablePayload = tableSlots.map(slotIdToString);
      bc.broadcastPartie('table_sync', { slots: tablePayload });
      bc.onTableSync(tableSlots);
      tableSlots = null;
    }

    for (const s of slots) {
      bc.pushSlotAll(s);
    }
    slots.clear();

    if (wantTurn) {
      bc.pushTurnAll();
      wantTurn = false;
    }

    if (messages.length) {
      for (const m of messages) {
        if (m.to) {
          const list = Array.isArray(m.to) ? m.to : [m.to];
          for (const u of list) {
            bc.sendToUser(u, m.type, m.data);
          }
        } else {
          bc.broadcastPartie(m.type, m.data);
        }
      }
      messages.length = 0;
    }
  };

  return { touch, touchMany, syncTable, turn, message, flush };
}
