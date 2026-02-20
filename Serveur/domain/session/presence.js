// services/session/presence.js v1.1
import { ensureGameMeta } from "../../game/meta.js";
import { pauseTurnClock, resumeTurnClock } from "../../game/turnClock.js";

/**
 * Presence/session : déconnexion / reconnexion + wrapper close WS.
 * Objectif: sortir "close/disconnect/reconnect" de Serveur.js et de handlers/gameEnd.js
 * sans changer le comportement.
 */
export function createPresence(ctx) {
  const {
    state,

    // roles/helpers
    detachSpectator,
    clearInvitesForUser,

    // transport
    sendEvtUser,

    // saves
    saveGameState,
    loadGameState,

    // lobby
    refreshLobby,

    // misc
    notifyOpponent,
    emitStartGameToUser,
    emitSnapshotsToAudience,
  } = ctx;
  const {
    games,
    gameMeta,
    gameSpectators,
    userToGame,
    userToSpectate,
    userByWs,
    wsByUser,
  } = state;

  function pauseTurnForDisconnect(game) {
    if (!game?.turn) return false;
    return pauseTurnClock(game.turn, Date.now());
  }

  function resumeTurnAfterReconnect(game) {
    if (!game?.turn) return false;
    return resumeTurnClock(game.turn, Date.now());
  }

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
    const paused = pauseTurnForDisconnect(game);

    saveGameState(game_id, game);
    if (paused) {
      emitSnapshotsToAudience(game_id, { reason: "opponent_disconnect_pause" });
    }

    for (const p of game.players) {
      if (p !== username) {
        sendEvtUser(p, "opponent_disconnected", { game_id, username });
      }
    }

    const spectators = gameSpectators.get(game_id);
    if (spectators?.size) {
      for (const s of spectators) {
        if (s && s !== username) {
          sendEvtUser(s, "opponent_disconnected", { game_id, username });
        }
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
    let resumed = false;
    if (meta.disconnected.size === 0) {
      resumed = resumeTurnAfterReconnect(game);
    }

    // Retour direct en game pour le joueur reconnecté.
    emitStartGameToUser(username, game_id, { spectator: false });
    if (resumed) {
      emitSnapshotsToAudience(game_id, { reason: "opponent_rejoined_resume" });
    }

    notifyOpponent(game_id, game, "opponent_rejoined", { game_id, username });

    const spectators = gameSpectators.get(game_id);
    if (spectators?.size) {
      for (const s of spectators) {
        if (s && s !== username) {
          sendEvtUser(s, "opponent_rejoined", { game_id, username });
        }
      }
    }
  }

  function onSocketClose(ws) {
    const username = userByWs.get(ws);
    if (!username) return;

    // purge invites avant suppression wsByUser
    clearInvitesForUser(username);

    // garde association user->game pour reconnect (logique existante)
    handleDisconnect(username);

    userByWs.delete(ws);
    wsByUser.delete(username);

    refreshLobby();
  }

  return { handleDisconnect, handleReconnect, onSocketClose };
}
