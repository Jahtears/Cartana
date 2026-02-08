// turn.js - Système de tours

import {
  getSlotStack,
  makePlayerSlotId,
  getOrCreateTableSlot,
  cleanupEmptyTableSlots,
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
  const curDuration = Number(game.turn.durationMs ?? TURN_MS);

  // Si endsAt est déjà passé (latence / edge), on repart de "now"
  const base = Math.max(curEndsAt, now);
  game.turn.endsAt = base + bonusMs;

  // On augmente aussi durationMs pour garder une barre cohérente côté client
  game.turn.durationMs = curDuration + bonusMs;

  console.log("[TURN] BONUS_TIME", {
    current: game.turn.current,
    bonusMs,
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

  console.log("[TURN] SWITCH", { endedBy: actor, next, turnNumber: game.turn.number });

  return { next, given, recycled };
}