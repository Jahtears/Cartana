// domain/game/winConditions.js - Conditions de victoire

import { makePlayerSlotId, SLOT_TYPES, getSlotCount } from "./SlotManager.js";

/**
 * Vérifier si un joueur a gagné en vidant complètement son deck
 * @param {Object} game - État du jeu
 * @param {string} player - Le joueur à tester
 * @returns {boolean} true si le joueur a gagné
 */
export function hasWonByEmptyDeckSlot(game, player) {
  if (!player || !game) return false;

  const playerArrayIndex = game.players.indexOf(player);  // 0 ou 1
  if (playerArrayIndex === -1) return false;

  const playerIndex = playerArrayIndex + 1;  // 1 ou 2 pour SlotManager

  // Slot de deck = "iD1" (player index i=1 ou 2, Deck, slot 1)
  const deckSlot = makePlayerSlotId(playerIndex, SLOT_TYPES.DECK, 1);

  // Victoire si le deck est complètement vide
  return getSlotCount(game, deckSlot) === 0;
}

/**
 * Vérifier les conditions de victoire après une action
 * @param {Object} game - État du jeu
 * @param {string} player - Le joueur ayant joué
 * @returns {Object|null} {winner: player, reason: string} ou null
 */
export function checkWinCondition(game, player) {
  if (!game || !player) return null;

  // Condition 1: Joueur a vidé son deck
  if (hasWonByEmptyDeckSlot(game, player)) {
    return {
      winner: player,
      reason: "Deck complètement vide"
    };
  }

  // TODO: Ajouter d'autres conditions de victoire si existent
  // - Timeout (autre joueur ne joue pas à temps)
  // - Abandon
  // - etc.

  return null;
}

/**
 * Déterminer le gagnant d'une partie complète
 * @param {Object} game - État du jeu
 * @returns {string|null} Le gagnant ou null si pas de gagnant
 */
export function determineWinner(game) {
  if (!game || !game.players) return null;

  for (const player of game.players) {
    if (hasWonByEmptyDeckSlot(game, player)) {
      return player;
    }
  }

  return null;
}