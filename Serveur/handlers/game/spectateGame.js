//handlers\spectateGame.js
import { ensureGameMeta } from "../../domain/game/meta.js";
import { requireParam, getExistingGameOrRes, rejectIfBusyOrRes } from "../../net/guards.js";
 
 
 export function handleSpectateGame(ctx, ws, req, data, actor) {
   const {
     sendResponse,
     emitStartGameToUser,
     state,
     refreshLobby,

     attachSpectator,
   } = ctx;
 

  const game_id = requireParam(sendResponse, ws, req, data, "game_id");
  if (!game_id) return true;

  const game = getExistingGameOrRes(ctx, ws, req, game_id);
  if (!game) return true;

  // joueur interdit (un joueur est “busy”), spectateur OK
  if (rejectIfBusyOrRes(ctx, ws, req, actor, "Tu es déjà joueur dans une partie")) return true;
 
   ensureGameMeta(state.gameMeta, game_id, { initialSent: !!game?.turn });
 
   attachSpectator(game_id, actor);
 
   if (typeof emitStartGameToUser === "function") {
     emitStartGameToUser(actor, game_id, { spectator: true });
   }
 
   if (typeof refreshLobby === "function") refreshLobby();
 
   sendResponse(ws, req, true, { ok: true, game_id });
   return true;
 }
