// roles/roles.js v1.0

export const Activity = {
  LOBBY: "lobby",
  IN_GAME: "in_game",
  SPECTATING: "spectating",
};

export function createRoles(ctx) {
  const {
    wsByUser,
    userToGame,
    userToSpectate,
    gameSpectators,
    pendingInviteTo,
    inviteFrom,
    gameMeta,
    sendEvtUser,
  } = ctx;

  function _removeFromSpectatorsSet(username, gidOverride = null) {
    const gid = gidOverride ?? userToSpectate.get(username);
    if (!gid) return;

    const set = gameSpectators.get(gid);
    if (!set) return;

    set.delete(username);
    if (set.size === 0) gameSpectators.delete(gid);
  }

  /**
   * setUserActivity(username, Activity.*, game_id?)
   * - IN_GAME:    userToGame + remove spectator
   * - SPECTATING: userToSpectate + gameSpectators + remove player
   * - LOBBY:      clear both
   */
  function setUserActivity(username, activity, game_id = null) {
    const prevSpectate = userToSpectate.get(username) ?? null;

    // ✅ si on quitte spectate OU si on change de game_id en restant spectateur
    if (prevSpectate && (activity !== Activity.SPECTATING || prevSpectate !== game_id)) {
      _removeFromSpectatorsSet(username, prevSpectate);
      userToSpectate.delete(username);
    }

    if (activity === Activity.IN_GAME) {
      if (game_id) userToGame.set(username, game_id);
      else userToGame.delete(username);

      // ✅ ex-spectateur -> clean
      userToSpectate.delete(username);
      return;
    }

    if (activity === Activity.SPECTATING) {
      userToGame.delete(username);

      if (game_id) userToSpectate.set(username, game_id);
      else userToSpectate.delete(username);

      if (game_id) {
        if (!gameSpectators.has(game_id)) gameSpectators.set(game_id, new Set());
        gameSpectators.get(game_id).add(username);
      }
      return;
    }

    // LOBBY
    userToGame.delete(username);
    userToSpectate.delete(username);
  }

  /**
   * status = { online, activity, invite }
   */
  function getUserStatus(username) {
    const online = wsByUser.has(username);

    // activity
    let activity = { type: Activity.LOBBY };

    const spectateGameId = userToSpectate.get(username);
    if (spectateGameId) {
      activity = { type: Activity.LOBBY, spectating: spectateGameId };
    } else {
      const game_id = userToGame.get(username);
      if (game_id) {
        const meta = gameMeta.get(game_id);
        const result = !!meta?.result;
        activity = { type: Activity.IN_GAME, game_id, result };
      }
    }

    // invite
    let invite = null;
    const invToMe = pendingInviteTo.get(username);
    if (invToMe) {
      invite = { type: "invited", from: invToMe.from, createdAt: invToMe.createdAt };
    } else {
      const invitedTo = inviteFrom.get(username);
      const invFromMe = invitedTo ? pendingInviteTo.get(invitedTo) : null;
      if (invFromMe) {
        invite = { type: "inviting", to: invFromMe.to, createdAt: invFromMe.createdAt };
      }
    }

    return { online, activity, invite };
  }

  function attachSpectator(game_id, username) {
    setUserActivity(username, Activity.SPECTATING, game_id);
  }

  function detachSpectator(_game_id, username) {
    setUserActivity(username, Activity.LOBBY, null);
  }
  
  function isSpectator(game_id, username) {
    return userToSpectate.get(username) === game_id;
  }

  // ✅ utile sur disconnect: évite “invites fantômes”
  function clearInvitesForUser(username) {
    // si username était invité
    if (pendingInviteTo.has(username)) {
      const inv = pendingInviteTo.get(username);
      pendingInviteTo.delete(username);
      if (inv?.from) inviteFrom.delete(inv.from);
      if (inv?.from) {
        sendEvtUser(inv.from, "invite_cancelled", { to: username, reason: "offline" });
      }
    }

    // si username invitait quelqu’un
    const to = inviteFrom.get(username);
    if (to) {
      pendingInviteTo.delete(to);
      inviteFrom.delete(username);
      sendEvtUser(to, "invite_cancelled", { from: username, reason: "offline" });
    }
  }

  return {
    Activity,
    getUserStatus,
    setUserActivity,
    attachSpectator,
    detachSpectator,
    clearInvitesForUser,
    isSpectator,

  };
}
