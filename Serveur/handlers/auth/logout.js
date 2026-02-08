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

  // Set activity to offline
  if (typeof setUserActivity === "function") {
    setUserActivity(user, Activity.OFFLINE, null);
  }

  // Refresh lobby for other players
  if (typeof refreshLobby === "function") {
    refreshLobby();
  }

  // Send response confirming logout
  sendResponse(ws, req, true, { logged_out: true });

  return true;
}
