// turn.js - Système de tours

import {
  getSlotStack,
  makePlayerSlotId,
  getOrCreateTableSlot,
  cleanupEmptyTableSlots,
  getTableSlots,
  addTableSlot,
  removeCardFromSlot,
  putTop,
  SLOT_TYPES,
} from "./SlotManager.js";
import {
  refillEmptyHandSlotsFromPile,
  recycleFullTableSlotsToPile,
} from "./pileManager.js";

const TURN_MS = 15000;

/* =========================
   TURN SYSTEM
========================= */

const TURN_RANK = {
  "A": 13,
  "R": 12,
  "D": 11,
  "V": 10,
  "10": 9,
  "9": 8,
  "8": 7,
  "7": 6,
  "6": 5,
  "5": 4,
  "4": 3,
  "3": 2,
  "2": 1,
};

function valueRank(v) {
  // Valeur inconnue => 0 (perd contre tout ce qui est connu)
  return TURN_RANK[String(v)] ?? 0;
}

// Compare 2 cartes (par value uniquement)
function compareCardsByValue(c1, c2) {
  const r1 = c1 ? valueRank(c1.value) : 0;
  const r2 = c2 ? valueRank(c2.value) : 0;
  if (r1 > r2) return 1;
  if (r1 < r2) return -1;
  return 0;
}

function getOtherPlayer(game, player) {
  return (player === game.players[0]) ? game.players[1] : game.players[0];
}

function isAceValue(v) {
  const s = String(v ?? "");
  return s === "A" || s === "1";
}

function findAceInHand(game, username, handSize = 5) {
  const playerArrayIndex = game.players.indexOf(username);
  if (playerArrayIndex === -1) return null;

  const handSlot = makePlayerSlotId(playerArrayIndex + 1, SLOT_TYPES.HAND, 1);
  const stack = getSlotStack(game, handSlot);
  const start = Math.max(0, stack.length - handSize);

  // Priorise la carte la plus haute dans le stack pour rester cohérent avec "top = fin"
  for (let i = stack.length - 1; i >= start; i--) {
    const cardId = stack[i];
    const card = game.cardsById?.[cardId];
    if (card && isAceValue(card.value)) {
      return { slot_id: handSlot, card_id: cardId };
    }
  }
  return null;
}

function findOrCreateEmptyTableSlot(game) {
  const before = getTableSlots(game).length;
  const slot_id = getOrCreateTableSlot(game);
  const after = getTableSlots(game).length;
  return { slot_id, created: after > before };
}

function ensureOneEmptyTableSlot(game) {
  const tableSlots = getTableSlots(game);
  const hasEmpty = tableSlots.some((slotId) => getSlotStack(game, slotId).length === 0);
  if (hasEmpty) return false;
  addTableSlot(game);
  return true;
}

/**
 * Détermine qui commence :
 * - compare top card (index -1) du deck perso
 * - si égalité -> compare card -2 (index -2)
 * - si encore égal -> fallback player[0]
 */
export function initTurnForGame(game) {
  const p1 = game.players[0];
  const p2 = game.players[1];

  // SlotManager attend playerIndex = 1 ou 2
  const d1Ids = getSlotStack(game, makePlayerSlotId(1, SLOT_TYPES.DECK, 1));  // Player 1
  const d2Ids = getSlotStack(game, makePlayerSlotId(2, SLOT_TYPES.DECK, 1));  // Player 2

  const top1Id = d1Ids.length ? d1Ids[d1Ids.length - 1] : null;
  const top2Id = d2Ids.length ? d2Ids[d2Ids.length - 1] : null;

  const top1 = top1Id ? (game.cardsById?.[top1Id] ?? null) : null;
  const top2 = top2Id ? (game.cardsById?.[top2Id] ?? null) : null;

  let cmp = compareCardsByValue(top1, top2);

  if (cmp === 0) {
    const top1bId = d1Ids.length > 1 ? d1Ids[d1Ids.length - 2] : null;
    const top2bId = d2Ids.length > 1 ? d2Ids[d2Ids.length - 2] : null;

    const top1b = top1bId ? (game.cardsById?.[top1bId] ?? null) : null;
    const top2b = top2bId ? (game.cardsById?.[top2bId] ?? null) : null;

    cmp = compareCardsByValue(top1b, top2b);
  }

  const starter = (cmp >= 0) ? p1 : p2;
  game.turn = { current: starter, number: 1 };
  game.turn.durationMs = TURN_MS;
  game.turn.endsAt = Date.now() + TURN_MS;
  game.turn.paused = false;
  game.turn.remainingMs = 0;

  console.log("[TURN] INIT", {
    starter,
    p1_top: top1 ? top1.value : null,
    p2_top: top2 ? top2.value : null,
  });

  return { starter, reason: "A vous de commencer" };
}

/* =========================
   PILE / REFILL
========================= */

// Les fonctions de pile ont été déplacées vers pileManager.js
// - drawFromPile
// - refillEmptyHandSlotsFromPile
// - recycleFullTableSlotsToPile

/* =========================
   TURN BONUS
========================= */

/**
 * Ajouter du temps bonus au tour courant
 * (serveur = source de vérité)
 * @param {Object} game - État du jeu
 * @param {number} bonusMs - Temps bonus en ms
 * @returns {boolean} true si succès
 */
export function addTurnBonusTime(game, bonusMs = 10000) {
  if (!game?.turn) return false;

  const now = Date.now();
  const curEndsAt = Number(game.turn.endsAt ?? 0);
  const safeBonus = Math.max(0, Number(bonusMs) || 0);
  const remaining = Math.max(0, curEndsAt - now);

  // Le timer ne doit jamais dépasser sa valeur initiale (TURN_MS).
  const nextRemaining = Math.min(TURN_MS, remaining + safeBonus);
  game.turn.endsAt = now + nextRemaining;
  game.turn.durationMs = TURN_MS;
  game.turn.paused = false;
  game.turn.remainingMs = 0;

  console.log("[TURN] BONUS_TIME", {
    current: game.turn.current,
    bonusMs: safeBonus,
    remainingBefore: remaining,
    remainingAfter: nextRemaining,
    endsAt: game.turn.endsAt,
    durationMs: game.turn.durationMs,
  });

  return true;
}

/**
 * Termine le tour du joueur actor (après pose sur B),
 * refill M vides de l'adversaire, puis switch turn.
 */
export function endTurnAfterBenchPlay(game, actor) {
  const recycled = recycleFullTableSlotsToPile(game);
  const next = getOtherPlayer(game, actor);

  if (recycled?.recycledSlots?.length) {
    getOrCreateTableSlot(game);
    cleanupEmptyTableSlots(game);
  }

  const given = refillEmptyHandSlotsFromPile(game, next, 5);

  game.turn = game.turn || { current: next, number: 1 };
  game.turn.current = next;
  game.turn.number = (game.turn.number ?? 1) + 1;

  // ✅ timebar serveur
  game.turn.durationMs = TURN_MS;
  game.turn.endsAt = Date.now() + TURN_MS;
  game.turn.paused = false;
  game.turn.remainingMs = 0;

  console.log("[TURN] SWITCH", { endedBy: actor, next, turnNumber: game.turn.number });

  return { next, given, recycled };
}

/**
 * Expire un tour si le timer est écoulé.
 * - auto-play d'un As de la main vers la table (si présent)
 * - pipeline canonique de fin de tour
 * - timer recalé à partir du timestamp fourni
 *
 * @returns {false|Object}
 */
export function timeoutTurnIfExpired(game, now = Date.now()) {
  const t = game?.turn;
  if (!t) return false;
  if (t.paused) return false;

  const endsAt = Number(t.endsAt ?? 0);
  if (!Number.isFinite(endsAt) || endsAt <= 0) return false;
  if (now < endsAt) return false;

  const prev = String(t.current ?? "").trim();
  if (!prev) return false;

  let playedAce = false;
  let aceFrom = null;
  let aceTo = null;
  let tableSyncNeeded = false;

  const ace = findAceInHand(game, prev, 5);
  if (ace) {
    const { slot_id: tableSlot, created } = findOrCreateEmptyTableSlot(game);
    const removed = removeCardFromSlot(game, ace.slot_id, ace.card_id);
    if (removed) {
      putTop(game, tableSlot, ace.card_id);
      playedAce = true;
      aceFrom = ace.slot_id;
      aceTo = tableSlot;
      tableSyncNeeded = !!created;
      if (ensureOneEmptyTableSlot(game)) tableSyncNeeded = true;

      console.log("[TURN] TIMEOUT_AUTO_ACE", { prev, from: aceFrom, to: aceTo });
    }
  }

  const { next, given, recycled } = endTurnAfterBenchPlay(game, prev);

  // Le ticker externe peut fournir "now": on garde cette référence.
  game.turn.durationMs = TURN_MS;
  game.turn.endsAt = now + TURN_MS;
  game.turn.paused = false;
  game.turn.remainingMs = 0;

  const result = {
    expired: true,
    prev,
    next,
    given,
    recycled,
    playedAce,
    aceFrom,
    aceTo,
    tableSyncNeeded,
    endsAt: game.turn.endsAt,
    durationMs: game.turn.durationMs,
    turnNumber: game.turn.number,
  };

  console.log("[TURN] TIMEOUT_EXPIRED", {
    prev: result.prev,
    next: result.next,
    playedAce: result.playedAce,
    turnNumber: result.turnNumber,
  });

  return result;
}
