// handlers/login.js v2.0
import { resBadRequest, resServerError } from "../../net/transport.js";

export async function handleLogin(ctx, ws, req, data) {
  const {
    state,
    verifyOrCreateUser,
    getUserStatus,
    sendRes,
    refreshLobby,
    handleReconnect,
  } = ctx;

  // Safely handle undefined data
  const safeData = data ?? {};
  const username = String(safeData.username ?? "").trim();
  const pin = String(safeData.pin ?? "").trim();

  if (!username || !pin) {
    resBadRequest(sendRes, ws, req, "username/pin manquant");
    return true;
  }

  if (state.getWS(username)) {
    sendRes(ws, req, false, { code: "ALREADY_CONNECTED", message: "Utilisateur déjà connecté" });
    return true;
  }

  try {
    const ok = await verifyOrCreateUser(username, pin);
    if (!ok) {
      sendRes(ws, req, false, { code: "AUTH_BAD_PIN", message: "PIN incorrect" });
      return true;
    }

    state.registerUser(username, ws);

    // Reconnexion: restaurer présence in-game si mapping existant.
    if (typeof handleReconnect === "function") {
      handleReconnect(username);
    }

    sendRes(ws, req, true, { username, status: getUserStatus(username) });
    if (typeof refreshLobby === "function") refreshLobby();
    return true;
    
  } catch (err) {
    console.error("Erreur login:", err);
    resServerError(sendRes, ws, req, "Erreur serveur");
    return true;
  }
}
