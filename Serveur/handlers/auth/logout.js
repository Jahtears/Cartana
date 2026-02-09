// handlers/auth/logout.js - Handle user logout

export function handleLogout(ctx, ws, req, data, actor) {
  const {
    state,
    sendResponse,
    clearInvitesForUser,
    setUserActivity,
    Activity,
    refreshLobby,
  } = ctx;

  // Unregister user from state
  const user = actor; // actor is the authenticated user
  state.unregisterUser(user, ws);

  // Clear invites
  if (typeof clearInvitesForUser === "function") {
    clearInvitesForUser(user);
  }

  // Sortie explicite de session: retour lobby + detach des mappings.
  if (typeof setUserActivity === "function") {
    setUserActivity(user, Activity.LOBBY, null);
  }

  // Refresh lobby for other players
  if (typeof refreshLobby === "function") {
    refreshLobby();
  }

  // Send response confirming logout
  sendResponse(ws, req, true, { logged_out: true });

  return true;
}
