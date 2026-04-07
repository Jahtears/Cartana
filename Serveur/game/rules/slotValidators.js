import { SlotId, SLOT_TYPES } from '../constants/slots.js';
import { getSlotStack } from '../state/slotStore.js';

const DEBUG = process.env.DEBUG_TRACE === '1';
const log = (...a) => DEBUG && console.log(...a);

const user = (code) => ({ valid: false, kind: 'user', code });
const tech = (reason) => ({ valid: false, kind: 'technical', debug_reason: reason });
const staticDeny = (code) => () => user(code);

export function validateTableSlot(game, card, _from, toSlotId) {
  if (!(toSlotId instanceof SlotId)) return tech('slot_id_not_canonical');
  if (!(game?.slots instanceof Map) || !game.slots.has(toSlotId))
    return tech('table_slot_not_found');

  const count = getSlotStack(game, toSlotId).length;

  const allowed = [
    ['A', 'R'],
    ['2', 'R'],
    ['3', 'R'],
    ['4', 'R'],
    ['5', 'R'],
    ['6', 'R'],
    ['7', 'R'],
    ['8', 'R'],
    ['9', 'R'],
    ['10', 'R'],
    ['V', 'R'],
    ['D'],
  ][count];

  if (!allowed || !allowed.includes(card.value)) {
    const accepted = allowed ? allowed.join(' ou ') : 'aucune';
    log('[RULES] TABLE_DENIED', { card: card.value, count, accepted });
    return { valid: false, kind: 'user', code: 'RULE_ALLOWED_ON_TABLE', params: { accepted } };
  }
  return { valid: true };
}

export const validateDeckSlot = staticDeny('RULE_MOVE_DENIED');
export const validateHandSlot = staticDeny('RULE_MOVE_DENIED');
export const validateDrawPileSlot = staticDeny('RULE_MOVE_DENIED');
export function validateBenchSlot() {
  return { valid: true };
}

export function getSlotValidator(slotId) {
  if (!(slotId instanceof SlotId)) return null;
  return (
    {
      [SLOT_TYPES.TABLE]: validateTableSlot,
      [SLOT_TYPES.DECK]: validateDeckSlot,
      [SLOT_TYPES.HAND]: validateHandSlot,
      [SLOT_TYPES.BENCH]: validateBenchSlot,
      [SLOT_TYPES.PILE]: validateDrawPileSlot,
    }[slotId.type] ?? null
  );
}
