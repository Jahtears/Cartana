// handlers/auth/logout.js - Handle user logout

export function handleLogout(ctx, ws, req, data, actor) {
  const {
    state,
    sendRes,
    clearInvitesForUser,
    setUserActivity,
    Activity,
    refreshLobby,
  } = ctx;

  // Unregister user from state
  const user = actor; // actor is the authenticated user
  state.unregisterUser(user, ws);

  // Clear invites
  clearInvitesForUser(user);

  // Sortie explicite de session: retour lobby + detach des mappings.
  setUserActivity(user, Activity.LOBBY, null);

  // Refresh lobby for other players
  refreshLobby();

  // Send response confirming logout
  sendRes(ws, req, true, { logged_out: true });

  return true;
}
