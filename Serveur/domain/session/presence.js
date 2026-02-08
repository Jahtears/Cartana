// services/session/presence.js v1.1
import { ensureGameMeta } from "../game/meta.js";

/**
 * Presence/session : déconnexion / reconnexion + wrapper close WS.
 * Objectif: sortir "close/disconnect/reconnect" de Serveur.js et de handlers/gameEnd.js
 * sans changer le comportement.
 */
export function createPresence(ctx) {
  const {
    // state
    games,
    gameMeta,
    userToGame,
    userToSpectate,
    userByWs,
    wsByUser,

    // roles/helpers
    detachSpectator,
    clearInvitesForUser,

    // transport
    sendEventToUser,

    // saves
    saveGameState,
    loadGameState,

    // lobby
    refreshLobby,

    // misc
    notifyOpponent,
  } = ctx;

  function handleDisconnect(username) {
    const spectate_id = userToSpectate.get(username);
    if (spectate_id) {
      detachSpectator(spectate_id, username);
      console.log("[SPECTATE] disconnected -> removed", { username, game_id: spectate_id });
      return;
    }

    const game_id = userToGame.get(username);
    if (!game_id) return;

    const game = games.get(game_id);
    if (!game) return;

    const meta = ensureGameMeta(gameMeta, game_id, { initialSent: false });
    meta.disconnected.add(username);
    meta.lastSeen[username] = Date.now();

    saveGameState(game_id, game);

    for (const p of game.players) {
      if (p !== username) {
        sendEventToUser(p, "opponent_disconnected", { game_id, username });
      }
    }
  }

  function handleReconnect(username) {
    // 1) spectateur: rien à faire
    const spectate_id = userToSpectate.get(username);
    if (spectate_id) return;

    // 2) joueur
    const game_id = userToGame.get(username);
    if (!game_id) return;

    let game = games.get(game_id);

    if (!game) {
      const loaded = loadGameState(game_id);
      if (loaded) {
        game = loaded;
        games.set(game_id, game);
        console.log("[RECONNECT] game loaded from save", game_id);
      } else {
        console.warn("[RECONNECT] no in-mem game and no save", { username, game_id });
        return;
      }
    }

    const meta = ensureGameMeta(gameMeta, game_id, { initialSent: !!game.turn });
    meta.disconnected.delete(username);
    meta.lastSeen[username] = Date.now();

    if (typeof notifyOpponent === "function") {
      notifyOpponent(game_id, game, "opponent_online", { username, where: "lobby" });
    } else {
      for (const p of game.players) {
        if (p !== username) {
          sendEventToUser(p, "opponent_online", { game_id, username, where: "lobby" });
        }
      }
    }
  }

  function onSocketClose(ws) {
    const username = userByWs.get(ws);
    if (!username) return;

    // purge invites avant suppression wsByUser
    if (typeof clearInvitesForUser === "function") {
      clearInvitesForUser(username);
    }

    // garde association user->game pour reconnect (logique existante)
    handleDisconnect(username);

    userByWs.delete(ws);
    wsByUser.delete(username);

    if (typeof refreshLobby === "function") refreshLobby();
  }

  return { handleDisconnect, handleReconnect, onSocketClose };
}
