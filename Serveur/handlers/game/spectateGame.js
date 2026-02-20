//handlers\spectateGame.js
import { ensureGameMeta } from "../../game/meta.js";
import { requireParam, getExistingGameOrRes, rejectIfBusyOrRes } from "../../net/guards.js";
import { POPUP_MESSAGE } from "../../shared/popupMessages.js";

export function handleSpectateGame(ctx, ws, req, data, actor) {
  const {
    sendRes,
    emitStartGameToUser,
    state,
    refreshLobby,
    emitFullState,
    sendEvtSocket,
    attachSpectator,
  } = ctx;
  const { userToSpectate, wsByUser, gameMeta } = state;

  const game_id = requireParam(sendRes, ws, req, data, "game_id");
  if (!game_id) return true;

  const game = getExistingGameOrRes(ctx, ws, req, game_id);
  if (!game) return true;

  // joueur interdit spectateur OK
  if (rejectIfBusyOrRes(ctx, ws, req, actor, POPUP_MESSAGE.TECH_BAD_STATE)) return true;

  const alreadySpectatingThisGame = userToSpectate.get(actor) === game_id;
  const meta = ensureGameMeta(gameMeta, game_id, { initialSent: !!game?.turn });

  attachSpectator(game_id, actor);

  // Premier passage depuis le lobby: notifier l'entree en mode spectateur.
  if (!alreadySpectatingThisGame) {
    emitStartGameToUser(actor, game_id, { spectator: true });
  }

  // Resync explicite (depuis l'ecran Game): snapshot complet spectateur.
  if (
    alreadySpectatingThisGame &&
    meta.initialSent
  ) {
    emitFullState(game, actor, wsByUser, sendEvtSocket, { view: "spectator", gameMeta, game_id });
  }

  if (!alreadySpectatingThisGame) refreshLobby();

  sendRes(ws, req, true, {
    ok: true,
    game_id,
    spectator: true,
    waiting: !meta.initialSent,
    rejoined: alreadySpectatingThisGame,
  });
  return true;
}
