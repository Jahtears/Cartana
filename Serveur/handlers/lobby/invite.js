// handlers/invite.js v1.0
import { ensureGameMeta } from "../../game/meta.js";
import { requireParam } from "../../net/guards.js";
import { resError } from "../../net/transport.js";
import { emitPopupMessage } from "../../shared/uiMessage.js";
import { POPUP_MESSAGE } from "../../shared/popupMessages.js";
import { cleanupIfOrphaned, ensureGameEndMeta, POST_GAME_STATES } from "../game/gameEnd.js";

const INVITE_CONTEXT_REMATCH = "rematch";

function normalizeInviteContext(data) {
  const context = String(data?.context ?? "").trim().toLowerCase();
  const source_game_id = String(data?.source_game_id ?? "").trim();

  if (context === INVITE_CONTEXT_REMATCH) {
    return {
      context: INVITE_CONTEXT_REMATCH,
      source_game_id,
    };
  }

  return {
    context: "",
    source_game_id: "",
  };
}

function resolveRematchOpponent(game, actor) {
  if (!game || !Array.isArray(game.players)) return "";
  const players = game.players.filter((p) => typeof p === "string" && p.trim());
  if (!players.includes(actor)) return "";
  return players.find((p) => p !== actor) ?? "";
}

function validateRematchInviteOrRes(ctx, ws, req, actor, to, source_game_id) {
  const { state, sendRes } = ctx;
  const { games, gameMeta, wsByUser } = state;

  if (!source_game_id) {
    resError(sendRes, ws, req, POPUP_MESSAGE.TECH_BAD_REQUEST, {
      field: "source_game_id",
      message_params: { field: "source_game_id" },
    });
    return null;
  }

  const sourceGame = games.get(source_game_id);
  if (!sourceGame) {
    resError(sendRes, ws, req, POPUP_MESSAGE.TECH_NOT_FOUND);
    return null;
  }

  const opponent = resolveRematchOpponent(sourceGame, actor);
  if (!opponent || opponent !== to) {
    resError(sendRes, ws, req, POPUP_MESSAGE.TECH_FORBIDDEN);
    return null;
  }

  const sourceMeta = ensureGameEndMeta(gameMeta, source_game_id, { initialSent: true });
  if (!sourceMeta?.result) {
    resError(sendRes, ws, req, POPUP_MESSAGE.TECH_BAD_STATE);
    return null;
  }

  const targetOnline = wsByUser.has(to);
  const targetDisconnected = sourceMeta.disconnected instanceof Set && sourceMeta.disconnected.has(to);
  if (!targetOnline || targetDisconnected) {
    resError(sendRes, ws, req, POPUP_MESSAGE.TECH_BAD_STATE);
    return null;
  }

  return { sourceGame, sourceMeta };
}

function markRematchResolved(state, source_game_id) {
  if (!source_game_id) return;
  const meta = state.gameMeta.get(source_game_id);
  if (!meta || typeof meta !== "object") return;
  meta.post_game_state = POST_GAME_STATES.RESOLVED;
}

export function handleInvite(ctx, ws, req, data, actor) {
  const {
    state,
    sendRes,
    sendEvtUser,
    refreshLobby,
  } = ctx;
  const { pendingInviteTo, inviteFrom } = state;

  const to = requireParam(sendRes, ws, req, data, "to");
  if (!to) return true;
  const { context, source_game_id } = normalizeInviteContext(data);
  let rematchMeta = null;

  if (context === INVITE_CONTEXT_REMATCH) {
    const rematchValidation = validateRematchInviteOrRes(ctx, ws, req, actor, to, source_game_id);
    if (!rematchValidation) return true;
    rematchMeta = rematchValidation.sourceMeta;
  }


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
  if (inviteFrom.has(to)) {
    return resError(
      sendRes,
      ws,
      req,
      POPUP_MESSAGE.INVITE_TARGET_ALREADY_INVITING
    );
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
  if (inviteFrom.has(actor)) {
    return resError(
      sendRes,
      ws,
      req,
      POPUP_MESSAGE.INVITE_ACTOR_ALREADY_INVITING
    );
  }

  if (rematchMeta) {
    rematchMeta.post_game_state = POST_GAME_STATES.REMATCH_PENDING;
  }

  const invite = {
    from: actor,
    to,
    createdAt: Date.now(),
    context,
    source_game_id,
  };
  pendingInviteTo.set(to, invite);
  inviteFrom.set(actor, to);

  const inviteRequestPayload = { from: actor };
  if (context) inviteRequestPayload.context = context;
  if (source_game_id) inviteRequestPayload.source_game_id = source_game_id;

  sendEvtUser(to, "invite_request", inviteRequestPayload);

  const resPayload = { sent: true };
  if (context) resPayload.context = context;
  if (source_game_id) resPayload.source_game_id = source_game_id;
  sendRes(ws, req, true, resPayload);

  refreshLobby();

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
  const { pendingInviteTo, inviteFrom, games, gameMeta } = state;

  const to = requireParam(sendRes, ws, req, data, "to");
  if (!to) return true;
  const accepted = !!data.accepted;
 
  const pending = pendingInviteTo.get(actor);
  if (!pending || pending.from !== to) {
    return resError(sendRes, ws, req, POPUP_MESSAGE.INVITE_NOT_FOUND);
  }

  const context = String(pending.context ?? "").trim().toLowerCase();
  const source_game_id = String(pending.source_game_id ?? "").trim();

  pendingInviteTo.delete(actor);
  inviteFrom.delete(pending.from);

  if (!accepted) {
    if (context === INVITE_CONTEXT_REMATCH) {
      markRematchResolved(state, source_game_id);

      emitPopupMessage(
        sendEvtUser,
        [to, actor],
        "rematch_declined",
        {
          accepted: false,
          from: actor,
          to,
          context,
          source_game_id,
        },
        {
          message_code: POPUP_MESSAGE.INVITE_DECLINED,
          message_params: { actor },
        }
      );

      setUserActivity(actor, Activity.LOBBY, null);
      setUserActivity(to, Activity.LOBBY, null);

      if (source_game_id) {
        cleanupIfOrphaned(ctx, source_game_id, { reason: "rematch_declined" });
      }

      sendRes(ws, req, true, {
        accepted: false,
        context,
        source_game_id,
      });
      refreshLobby();
      return true;
    }

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
    sendRes(ws, req, true, { accepted: false, context, source_game_id });

    refreshLobby();

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

  if (context === INVITE_CONTEXT_REMATCH && source_game_id) {
    markRematchResolved(state, source_game_id);
    cleanupIfOrphaned(ctx, source_game_id, { reason: "rematch_accept" });
  }

  refreshLobby();
  emitStartGameToUser(actor, game_id, { spectator: false });
  emitStartGameToUser(to, game_id, { spectator: false });

  sendRes(ws, req, true, {
    accepted: true,
    game_id,
    players: game.players,
    context,
    source_game_id,
  });
  return true;
}
