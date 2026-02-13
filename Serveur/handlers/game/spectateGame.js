//handlers\spectateGame.js
import { ensureGameMeta } from "../../domain/game/meta.js";
import { requireParam, getExistingGameOrRes, rejectIfBusyOrRes } from "../../net/guards.js";
import { POPUP_MESSAGE } from "../../shared/popupMessages.js";
 
 
 export function handleSpectateGame(ctx, ws, req, data, actor) {
   const {
     sendRes,
     emitStartGameToUser,
     state,
     refreshLobby,

     attachSpectator,
   } = ctx;
 

  const game_id = requireParam(sendRes, ws, req, data, "game_id");
  if (!game_id) return true;

  const game = getExistingGameOrRes(ctx, ws, req, game_id);
  if (!game) return true;

  // joueur interdit (un joueur est “busy”), spectateur OK
  if (rejectIfBusyOrRes(ctx, ws, req, actor, POPUP_MESSAGE.TECH_BAD_STATE)) return true;
 
   ensureGameMeta(state.gameMeta, game_id, { initialSent: !!game?.turn });
 
   attachSpectator(game_id, actor);
 
   if (typeof emitStartGameToUser === "function") {
     emitStartGameToUser(actor, game_id, { spectator: true });
   }
 
   if (typeof refreshLobby === "function") refreshLobby();
 
   sendRes(ws, req, true, { ok: true, game_id });
   return true;
 }
