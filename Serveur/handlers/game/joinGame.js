// handlers/joinGame.js
import { ensureGameMeta } from "../../game/meta.js";
import { TURN_FLOW_MESSAGES } from "../../game/helpers/turnFlowHelpers.js";
import { emitGameMessage } from "../../shared/uiMessage.js";
import { requireParam, getExistingGameOrRes } from "../../net/guards.js";
import { resBadState, resForbidden } from "../../net/transport.js";
import { saveGameState } from "../../domain/session/Saves.js";
import { POPUP_MESSAGE } from "../../shared/popupMessages.js";


export function handleJoinGame(ctx, ws, req, data, actor) {
  const {
    state,
    sendRes,
    sendEvtUser,
    emitStartGameToUser,
    emitFullState,
    sendEvtSocket,
    initTurnForGame,
    emitSnapshotsToAudience,
    refreshLobby,
    setUserActivity,
    Activity,
  } = ctx;
  const { userToGame, gameMeta, readyPlayers, gameSpectators, wsByUser } = state;

  const game_id = requireParam(sendRes, ws, req, data, "game_id");
  if (!game_id) return true;

  const game = getExistingGameOrRes(ctx, ws, req, game_id);
  if (!game) return true;

  // Interdire un join "hors players"
  if (!game.players.includes(actor)) {
    return resForbidden(sendRes, ws, req, POPUP_MESSAGE.TECH_FORBIDDEN);
  }

  const currentGameId = String(userToGame.get(actor) ?? "");
  if (currentGameId && currentGameId !== game_id) {
    return resBadState(sendRes, ws, req, POPUP_MESSAGE.TECH_BAD_STATE);
  }
  const alreadyInThisGame = currentGameId === game_id;

  const meta = ensureGameMeta(gameMeta, game_id, { initialSent: !!game?.turn });

  if (!alreadyInThisGame) {
    // Activité joueur et signal de démarrage uniquement lors de l'entrée depuis le lobby.
    setUserActivity(actor, Activity.IN_GAME, game_id);
    if (typeof emitStartGameToUser === "function") {
      emitStartGameToUser(actor, game_id, { spectator: false });
    }
    if (typeof refreshLobby === "function") refreshLobby();
    sendRes(ws, req, true, { ok: true, game_id, players: game.players, joining: true });
    return true;
  }

  // Resync/rejoin si la partie est déjà initialisée.
  if (meta.initialSent) {
    emitFullState(game, actor, wsByUser, sendEvtSocket, { view: "player", gameMeta, game_id });
    sendRes(ws, req, true, { ok: true, game_id, players: game.players, rejoined: true });
    return true;
  }

  // Barrière d'entrée: attendre que les 2 joueurs aient rejoint la scène.
  if (!readyPlayers.has(game_id)) readyPlayers.set(game_id, new Set());
  readyPlayers.get(game_id).add(actor);

  if (readyPlayers.get(game_id).size < game.players.length) {
    sendRes(ws, req, true, { ok: true, game_id, players: game.players, waiting: true });
    return true;
  }

  const { starter, reason } = initTurnForGame(game);
  meta.initialSent = true;

  if (starter) {
    emitGameMessage(sendEvtUser, starter, {
      message_code: reason || TURN_FLOW_MESSAGES.START,
    });
  }

  if (typeof emitSnapshotsToAudience === "function") {
    emitSnapshotsToAudience(game_id, { reason: "init" });
  } else {
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

  saveGameState(game_id, game);
  sendRes(ws, req, true, { ok: true, game_id, players: game.players });
  return true;
}
