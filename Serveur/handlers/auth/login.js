// handlers/login.js v2.0
import { resBadRequest, resServerError } from "../../net/transport.js";

export async function handleLogin(ctx, ws, req, data) {
  const {
    state,
    verifyOrCreateUser,
    setUserActivity,
    Activity,
    getUserStatus,
    sendResponse,
    refreshLobby,
  } = ctx;

  // Safely handle undefined data
  const safeData = data ?? {};
  const username = String(safeData.username ?? "").trim();
  const pin = String(safeData.pin ?? "").trim();

  if (!username || !pin) {
    resBadRequest(sendResponse, ws, req, "username/pin manquant");
    return true;
  }

  if (state.getWS(username)) {
    sendResponse(ws, req, false, { code: "ALREADY_CONNECTED", message: "Utilisateur déjà connecté" });
    return true;
  }

  try {
    const ok = await verifyOrCreateUser(username, pin);
    if (!ok) {
      sendResponse(ws, req, false, { code: "AUTH_BAD_PIN", message: "PIN incorrect" });
      return true;
    }

    state.registerUser(username, ws);

    // Set user as ONLINE
    if (setUserActivity && Activity) {
      setUserActivity(username, Activity.ONLINE);
    }

    sendResponse(ws, req, true, { username, status: getUserStatus(username) });
    if (typeof refreshLobby === "function") refreshLobby();
    return true;
    
  } catch (err) {
    console.error("Erreur login:", err);
    resServerError(sendResponse, ws, req, "Erreur serveur");
    return true;
  }
}
