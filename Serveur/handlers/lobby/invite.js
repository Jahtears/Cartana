// handlers/invite.js v1.0
import { ensureGameMeta } from "../../domain/game/meta.js";
import { requireParam, rejectIfBusyOrRes } from "../../net/guards.js";
import { resError } from "../../net/transport.js";

export function handleInvite(ctx, ws, req, data, actor) {
  const {
    state,
    sendResponse,
    sendEventToUser,
    refreshLobby,
  } = ctx;
  const { pendingInviteTo } = state;

  const to = requireParam(sendResponse, ws, req, data, "to");
  if (!to) return true;

  if (rejectIfBusyOrRes(ctx, ws, req, actor, "Tu es déjà en partie")) return true;
  if (rejectIfBusyOrRes(ctx, ws, req, to, "Le joueur est déjà en partie")) return true;

  // destinataire a déjà une invite reçue
  if (pendingInviteTo.has(to)) {
      return resError(sendResponse, ws, req, "BUSY", "Le joueur a déjà une invitation en attente");
  }
  // destinataire invite déjà quelqu'un
  for (const inv of pendingInviteTo.values()) {
    if (inv.from === to) {
      return resError(sendResponse, ws, req, "BUSY", "Le joueur a déjà une invitation en cours");
    }
  }

  // acteur a déjà une invite reçue
  if (pendingInviteTo.has(actor)) {
    return resError(sendResponse, ws, req, "BUSY", "Tu as déjà une invitation en attente");
  }
  // acteur invite déjà quelqu'un
  for (const inv of pendingInviteTo.values()) {
    if (inv.from === actor) {
      return resError(sendResponse, ws, req, "BUSY", "Tu as déjà une invitation en cours");
    }
  }

  pendingInviteTo.set(to, { from: actor, to, createdAt: Date.now() });

  sendEventToUser(to, "invite_request", { from: actor });
  sendResponse(ws, req, true, { sent: true });

  if (typeof refreshLobby === "function") refreshLobby();

  return true;
}

export function handleInviteResponse(ctx, ws, req, data, actor) {
  const {
    state,
    sendResponse,
    sendEventToUser,
    refreshLobby,

    generateGameID,
    createGame,
    emitStartGameToUser,
    setUserActivity,
    Activity,
  } = ctx;
  const { pendingInviteTo, games, gameMeta } = state;

  const to = requireParam(sendResponse, ws, req, data, "to");
  if (!to) return true;
  const accepted = !!data.accepted;
 
  const pending = pendingInviteTo.get(actor);
  if (!pending || pending.from !== to) {
    return resError(sendResponse, ws, req, "NO_INVITE", "Aucune invitation correspondante");
  }
  pendingInviteTo.delete(actor);

  if (!accepted) {
    sendEventToUser(to, "invite_response", { message: `${actor} a refusé ton invitation` });
    sendResponse(ws, req, true, { accepted: false });

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

  sendResponse(ws, req, true, { accepted: true, game_id, players: game.players });
  return true;
}
