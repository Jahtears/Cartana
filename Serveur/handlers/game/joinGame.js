// handlers/joinGame.js v1.0
import { ensureGameMeta } from "../../domain/game/meta.js";
import { requireParam, getExistingGameOrRes, rejectIfBusyOrRes } from "../../net/guards.js";
import { resForbidden } from "../../net/transport.js";


export function handleJoinGame(ctx, ws, req, data, actor) {
  const {
    state,
    sendResponse,
    emitStartGameToUser,
    refreshLobby,
    setUserActivity,
    Activity,
  } = ctx;
  // ✅ join_game = cibler une ressource, mais interdit si déjà joueur ailleurs
  if (rejectIfBusyOrRes(ctx, ws, req, actor, "Tu es déjà joueur dans une partie")) return true;

  const game_id = requireParam(sendResponse, ws, req, data, "game_id");
  if (!game_id) return true;

  const game = getExistingGameOrRes(ctx, ws, req, game_id);
  if (!game) return true;


  // Interdire un join "hors players"
  if (!game.players.includes(actor)) {
  return resForbidden(sendResponse, ws, req, "Tu n'es pas joueur dans cette partie");
  }

  ensureGameMeta(state.gameMeta, game_id, { initialSent: !!game?.turn });

  // activité joueur
  setUserActivity(actor, Activity.IN_GAME, game_id);

  // start_game via notifier uniquement
  if (typeof emitStartGameToUser === "function") {
    emitStartGameToUser(actor, game_id, { spectator: false });
  }
  // aucun snapshot ici. Le client doit appeler ready_for_game.
  if (typeof refreshLobby === "function") refreshLobby();

  sendResponse(ws, req, true, { ok: true, game_id, players: game.players });
  return true;
}
