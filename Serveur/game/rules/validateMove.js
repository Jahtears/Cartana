import { SlotId, SLOT_TYPES } from '../constants/slots.js';
import { refillHandIfEmpty } from '../helpers/pileFlowHelpers.js';
import { slotTopHasAce, slotAnyHasAce } from '../state/cardStore.js';
import { hasCardInSlot, getSlotStack } from '../state/slotStore.js';
import { getSlotValidator } from './slotValidators.js';

// ── Helpers inline ──────────────────────────────────────────────────────────

const DEBUG = process.env.DEBUG_TRACE === '1' || process.env.GAME_DEBUG === '1';
const log = (...a) => DEBUG && console.log(...a);

const user = (code, params) => ({
  valid: false,
  kind: 'user',
  code,
  ...(params && Object.keys(params).length && { params }),
});
const tech = (reason) => ({ valid: false, kind: 'technical', debug_reason: reason });

// ── Règles globales ─────────────────────────────────────────────────────────

function hasWonByEmptyDeckSlot(game, player) {
  if (!player || !game) return false;
  const idx = game.players.indexOf(player);
  if (idx === -1) return false;
  const deck = SlotId.create(idx + 1, SLOT_TYPES.DECK, 1);
  return getSlotStack(game, deck).length === 0;
}

function hasLoseByEmptyPileSlot(game, player) {
  if (!game) return false;
  if (player && !game.players.includes(player)) return false;
  return getSlotStack(game, SlotId.create(0, SLOT_TYPES.PILE, 1)).length === 0;
}

function ruleCardMustBeInFromSlot(game, _p, card, fromSlotId) {
  if (!card?.id) return tech('card_unknown');
  if (!hasCardInSlot(game, fromSlotId, card.id)) {
    log('[RULES] source_slot_missing_card', {
      from_slot: fromSlotId,
      card_id: card.id,
      slot_content: getSlotStack(game, fromSlotId),
    });
    return tech('source_slot_missing_card');
  }
  return { valid: true };
}

function ruleFromMustBeClientPlayableSource(_g, _p, _c, fromSlotId) {
  const t = fromSlotId.type;
  if (t === SLOT_TYPES.HAND || t === SLOT_TYPES.DECK || t === SLOT_TYPES.BENCH)
    return { valid: true };
  if (t === SLOT_TYPES.PILE || t === SLOT_TYPES.TABLE) return tech('source_shared_forbidden');
  return tech('invalid_from_slot_type');
}

function ruleFromAndToMustDiffer(_g, _p, _c, fromSlotId, toSlotId) {
  return String(fromSlotId) === String(toSlotId) ? tech('same_slot_forbidden') : { valid: true };
}

function ruleTopOnlyForDeckAndBenchSource(game, _p, card, fromSlotId) {
  if (fromSlotId.type !== SLOT_TYPES.DECK && fromSlotId.type !== SLOT_TYPES.BENCH)
    return { valid: true };
  const stack = getSlotStack(game, fromSlotId);
  const top = stack.length ? stack[stack.length - 1] : null;
  return top && top === card.id ? { valid: true } : tech('source_card_not_top');
}

function ruleNotOnOpponentSide(game, player, _c, fromSlotId, toSlotId) {
  if (fromSlotId.player === 0 || toSlotId.player === 0) return { valid: true };
  const pi = player === game.players[0] ? 1 : player === game.players[1] ? 2 : null;
  if (pi === null) return tech('unknown_player');
  if (fromSlotId.player && fromSlotId.player !== 0 && fromSlotId.player !== pi)
    return user('RULE_OPPONENT_SLOT_FORBIDDEN');
  if (toSlotId.player && toSlotId.player !== 0 && toSlotId.player !== pi)
    return user('RULE_OPPONENT_SLOT_FORBIDDEN');
  return { valid: true };
}

function ruleDeckMustPlayOnTable(_g, _p, _c, fromSlotId, toSlotId) {
  return fromSlotId.type === SLOT_TYPES.DECK && toSlotId.type !== SLOT_TYPES.TABLE
    ? user('RULE_DECK_TO_TABLE')
    : { valid: true };
}

function ruleIsPlayersTurn(game, player) {
  if (!game?.turn?.current) return { valid: true };
  return game.turn.current !== player ? user('RULE_NOT_YOUR_TURN') : { valid: true };
}

function ruleBenchMustPlayOnTable(_g, _p, _c, fromSlotId, toSlotId) {
  return fromSlotId.type === SLOT_TYPES.BENCH && toSlotId.type !== SLOT_TYPES.TABLE
    ? user('RULE_BENCH_TO_TABLE')
    : { valid: true };
}

function ruleAceMustBePlayed(game, player, _c, _from, toSlotId) {
  if (toSlotId.type !== SLOT_TYPES.BENCH) return { valid: true };
  const pi = game.players.indexOf(player);
  if (pi === -1) return tech('unknown_player');
  const si = pi + 1;
  if (slotTopHasAce(game, SlotId.create(si, SLOT_TYPES.DECK, 1))) return user('RULE_ACE_ON_DECK');
  if (slotAnyHasAce(game, SlotId.create(si, SLOT_TYPES.HAND, 1))) return user('RULE_ACE_IN_HAND');
  return { valid: true };
}

// ── Point d'entrée unique ────────────────────────────────────────────────────

function validateMove(game, player, card, fromSlotId, toSlotId) {
  if (!card) return tech('card_unknown');
  if (!(fromSlotId instanceof SlotId) || !(toSlotId instanceof SlotId))
    return tech('slot_id_not_canonical');

  const rules = [
    ruleFromMustBeClientPlayableSource,
    ruleFromAndToMustDiffer,
    ruleCardMustBeInFromSlot,
    ruleTopOnlyForDeckAndBenchSource,
    ruleIsPlayersTurn,
    ruleNotOnOpponentSide,
    ruleDeckMustPlayOnTable,
    ruleBenchMustPlayOnTable,
    ruleAceMustBePlayed,
  ];

  for (const rule of rules) {
    const r = rule(game, player, card, fromSlotId, toSlotId);
    if (!r.valid) {
      log('[RULES] DENIED', {
        player,
        card_id: card.id,
        from: String(fromSlotId),
        to: String(toSlotId),
        kind: r.kind,
        code: r.code ?? r.debug_reason,
      });
      return r;
    }
  }

  const validator = getSlotValidator(toSlotId);
  if (!validator) return tech('slot_validator_missing');

  const sr = validator(game, card, fromSlotId, toSlotId);
  if (!sr.valid) {
    log('[RULES] DENIED_SLOT', { player, card_id: card.id, to: String(toSlotId) });
    return sr;
  }

  log('[RULES] OK', { player, card_id: card.id, from: String(fromSlotId), to: String(toSlotId) });
  return { valid: true };
}

export { validateMove, refillHandIfEmpty, hasWonByEmptyDeckSlot, hasLoseByEmptyPileSlot };
