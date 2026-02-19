// handlers/invite.js v1.0
import { ensureGameMeta } from "../../game/meta.js";
import { requireParam } from "../../net/guards.js";
import { resError } from "../../net/transport.js";
import { emitPopupMessage } from "../../shared/uiMessage.js";
import { POPUP_MESSAGE } from "../../shared/popupMessages.js";

export function handleInvite(ctx, ws, req, data, actor) {
  const {
    state,
    sendRes,
    sendEvtUser,
    refreshLobby,
  } = ctx;
  const { pendingInviteTo } = state;

  const to = requireParam(sendRes, ws, req, data, "to");
  if (!to) return true;


  // destinataire a déjà une invite reçue
  if (pendingInviteTo.has(to)) {
    return resError(
      sendRes,
      ws,
      req,
      POPUP_MESSAGE.INVITE_TARGET_ALREADY_INVITED
    );
  }
  // destinataire invite déjà quelqu'un
  for (const inv of pendingInviteTo.values()) {
    if (inv.from === to) {
      return resError(
        sendRes,
        ws,
        req,
        POPUP_MESSAGE.INVITE_TARGET_ALREADY_INVITING
      );
    }
  }

  // acteur a déjà une invite reçue
  if (pendingInviteTo.has(actor)) {
    return resError(
      sendRes,
      ws,
      req,
      POPUP_MESSAGE.INVITE_ACTOR_ALREADY_INVITED
    );
  }
  // acteur invite déjà quelqu'un
  for (const inv of pendingInviteTo.values()) {
    if (inv.from === actor) {
      return resError(
        sendRes,
        ws,
        req,
        POPUP_MESSAGE.INVITE_ACTOR_ALREADY_INVITING
      );
    }
  }

  pendingInviteTo.set(to, { from: actor, to, createdAt: Date.now() });

  sendEvtUser(to, "invite_request", { from: actor });
  sendRes(ws, req, true, { sent: true });

  if (typeof refreshLobby === "function") refreshLobby();

  return true;
}

export function handleInviteResponse(ctx, ws, req, data, actor) {
  const {
    state,
    sendRes,
    sendEvtUser,
    refreshLobby,

    generateGameID,
    createGame,
    emitStartGameToUser,
    setUserActivity,
    Activity,
  } = ctx;
  const { pendingInviteTo, games, gameMeta } = state;

  const to = requireParam(sendRes, ws, req, data, "to");
  if (!to) return true;
  const accepted = !!data.accepted;
 
  const pending = pendingInviteTo.get(actor);
  if (!pending || pending.from !== to) {
    return resError(sendRes, ws, req, POPUP_MESSAGE.INVITE_NOT_FOUND);
  }
  pendingInviteTo.delete(actor);

  if (!accepted) {
    emitPopupMessage(
      sendEvtUser,
      to,
      "invite_response",
      {
        accepted: false,
        from: actor,
        to,
      },
      {
        message_code: POPUP_MESSAGE.INVITE_DECLINED,
        message_params: { actor },
      }
    );
    sendRes(ws, req, true, { accepted: false });

    if (typeof refreshLobby === "function") refreshLobby();

    return true;
  }

  // ✅ créer game
  const game_id = generateGameID();
  const game = createGame(actor, to);
  games.set(game_id, game);

  ensureGameMeta(gameMeta, game_id, { initialSent: false });

  // ✅ activité: si actor/to étaient spectateurs -> ils passent joueur (nettoyage auto)
  setUserActivity(actor, Activity.IN_GAME, game_id);
  setUserActivity(to, Activity.IN_GAME, game_id);

  if (typeof refreshLobby === "function") refreshLobby();

  if (typeof emitStartGameToUser === "function") {
    emitStartGameToUser(actor, game_id, { spectator: false });
    emitStartGameToUser(to, game_id, { spectator: false });
  }

  sendRes(ws, req, true, { accepted: true, game_id, players: game.players });
  return true;
}
