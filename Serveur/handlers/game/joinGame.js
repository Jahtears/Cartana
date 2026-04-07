import { ensureGameMeta } from '../../game/meta.js';
import { emitRule, POPUP } from '../../shared/messages.js';
import { requireParam, getExistingGameOrRes } from '../../net/guards.js';
import { resError } from '../../net/transport.js';
import { saveGameState } from '../../domain/session/Saves.js';

export function handleJoinGame(ctx, ws, req, data, actor) {
  const sessionUsecases = ctx.usecases?.session ?? ctx;
  const turnUsecases = ctx.usecases?.turn ?? ctx;

  const { state, sendRes, sendEvtUser, refreshLobby, setUserActivity, Activity } = ctx;
  const { emitStartGameToUser, emitFullState, emitSnapshotsToAudience } = sessionUsecases;
  const { initTurnForGame } = turnUsecases;
  const { userToGame, userToEndGame, gameMeta, readyPlayers, wsByUser } = state;

  const game_id = requireParam(sendRes, ws, req, data, 'game_id');
  if (!game_id) return true;

  const game = getExistingGameOrRes(ctx, ws, req, game_id);
  if (!game) return true;

  if (!game.players.includes(actor)) return resError(sendRes, ws, req, POPUP.FORBIDDEN);

  const currentGameId = String(userToGame.get(actor) ?? '');
  if (currentGameId && currentGameId !== game_id)
    return resError(sendRes, ws, req, POPUP.BAD_STATE);

  const alreadyInThisGame = currentGameId === game_id;
  const meta = ensureGameMeta(gameMeta, game_id, { initialSent: Boolean(game?.turn) });

  if (!alreadyInThisGame) {
    setUserActivity(actor, Activity.IN_GAME, game_id);
    emitStartGameToUser(actor, game_id, { spectator: false });
    refreshLobby();
    sendRes(ws, req, true, { ok: true, game_id, players: game.players, joining: true });
    return true;
  }

  if (meta.initialSent) {
    emitFullState(game, actor, wsByUser, ctx.sendEvtSocket, {
      gameMeta,
      game_id,
      userToGame,
      userToEndGame,
    });
    sendRes(ws, req, true, { ok: true, game_id, players: game.players, rejoined: true });
    return true;
  }

  if (!readyPlayers.has(game_id)) readyPlayers.set(game_id, new Set());
  readyPlayers.get(game_id).add(actor);

  if (readyPlayers.get(game_id).size < game.players.length) {
    sendRes(ws, req, true, { ok: true, game_id, players: game.players, waiting: true });
    return true;
  }

  const { starter, reason } = initTurnForGame(game);
  meta.initialSent = true;

  if (starter) emitRule(sendEvtUser, starter, reason); // ← emitRule au lieu de emitGameMessage

  emitSnapshotsToAudience(game_id, { reason: 'init' });
  saveGameState(game_id, game);
  sendRes(ws, req, true, { ok: true, game_id, players: game.players });
  return true;
}
