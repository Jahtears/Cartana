// handlers/readyForGame.js v2.0 - Adapté pour architecture slots unifiée

import { ensureGameMeta } from "../../domain/game/meta.js";
import { TURN_FLOW_MESSAGES } from "../../domain/game/helpers/turnFlowHelpers.js";
import { GAME_MESSAGE } from "../../shared/constants.js";
import { emitGameMessage } from "../../shared/uiMessage.js";
import { getExistingGameOrRes, getGameIdFromDataOrMapping } from "../../net/guards.js";
import { resBadRequest, resForbidden } from "../../net/transport.js";
import { saveGameState } from "../../domain/session/Saves.js";
import { POPUP_MESSAGE } from "../../shared/popupMessages.js";

export function handleReadyForGame(ctx, ws, req, data, actor) {
  const {
    state,
    sendRes,
    sendEvtUser,

    // transport
    sendEvtSocket,

    // NEW API (Game.js)
    emitFullState,

    // init turn
    initTurnForGame,
    emitSnapshotsToAudience,
  } = ctx;
  const { gameMeta, readyPlayers, gameSpectators, userToGame, wsByUser } = state;

  // ------------------------------------------------------------------
  // 1) CAS JOUEUR D'ABORD 
  // ------------------------------------------------------------------
  const playerGameId = userToGame.get(actor) ?? null;
  if (playerGameId) {
    const game = getExistingGameOrRes(ctx, ws, req, playerGameId);
    if (!game) return true;
    const game_id = playerGameId;

    // readyPlayers
    if (!readyPlayers.has(game_id)) readyPlayers.set(game_id, new Set());
    readyPlayers.get(game_id).add(actor);

    // meta
    const meta = ensureGameMeta(gameMeta, game_id, { initialSent: !!game?.turn });

    // Rejoin / resync si déjà initialisé
    if (meta.initialSent) {
      emitFullState(game, actor, wsByUser, sendEvtSocket, { view: "player", gameMeta, game_id });
      sendRes(ws, req, true, { ok: true, rejoined: true });
      return true;
    }

    // Attendre les 2 joueurs
    if (readyPlayers.get(game_id).size < game.players.length) {
      sendRes(ws, req, true, { ok: true, waiting: true });
      return true;
    }
    
    // Init le système de tours (détermine qui commence)
    const { starter, reason } = initTurnForGame(game);
    meta.initialSent = true;

    if (starter) {
      // Contrat UI "show_game_message":
      // - text: libellé affiché
      // - code: identifiant sémantique (couleur côté client)
      // - color: fallback legacy
      emitGameMessage(
        sendEvtUser,
        starter,
        {
          text: reason || TURN_FLOW_MESSAGES.START,
          code: GAME_MESSAGE.TURN_START,
       },
        { code: GAME_MESSAGE.INFO }
      );
    }

    // ✅ snapshot complet à l'audience (joueurs + spectateurs) via notifier
    if (typeof emitSnapshotsToAudience === "function") {
      emitSnapshotsToAudience(game_id, { reason: "init" });
    } else {
      // fallback robuste (ancien comportement)
      for (const p of game.players) {
        emitFullState(game, p, wsByUser, sendEvtSocket, { view: "player", gameMeta, game_id });
      }
      const specs = gameSpectators.get(game_id);
      if (specs && specs.size) {
        for (const s of specs) {
          emitFullState(game, s, wsByUser, sendEvtSocket, { view: "spectator", gameMeta, game_id });
        }
      }
    }
    
    sendRes(ws, req, true, { ok: true });
    saveGameState(game_id, game);
    return true;
  }

  // ------------------------------------------------------------------
  // 2) CAS SPECTATEUR (uniquement si pas joueur)
  // ------------------------------------------------------------------

  const requestedGameId =
    getGameIdFromDataOrMapping(ctx, ws, req, data, actor, {
      required: false,
      preferMapping: true,
      allowedKeys: ["game_id"],
    }) ?? "";

  if (!requestedGameId) {
    // spectateur sans mapping et sans game_id => demande invalide
    resBadRequest(sendRes, ws, req, POPUP_MESSAGE.TECH_BAD_REQUEST);
    return true;
  }

  const game = getExistingGameOrRes(ctx, ws, req, requestedGameId);
  if (!game) return true;

  const specs = gameSpectators.get(requestedGameId);
  const isSpec = !!(specs && specs.has(actor));
  if (!isSpec) {
    resForbidden(sendRes, ws, req, POPUP_MESSAGE.TECH_FORBIDDEN);
    return true;
  }

  const meta = ensureGameMeta(gameMeta, requestedGameId, { initialSent: !!game?.turn });
  if (!meta.initialSent) {
    sendRes(ws, req, true, { ok: true, waiting: true });
    return true;
  }

  emitFullState(game, actor, wsByUser, sendEvtSocket, { view: "spectator", gameMeta, game_id: requestedGameId });
  sendRes(ws, req, true, { ok: true, spectator: true });
  return true;
}
