// lobby/lists.js

export function createLobbyRefresher({ broadcastPlayersList, broadcastGamesList }) {
  return function refreshLobby() {
    if (typeof broadcastPlayersList === "function") broadcastPlayersList();
    if (typeof broadcastGamesList === "function") broadcastGamesList();
  };
}

export function createLobbyLists(ctx) {
  const {
    games,
    gameMeta,
    gameSpectators,
    wsByUser,
    sendLobbyEvent,
    getUserStatus,
  } = ctx;

  function gamesList() {
    return [...games.entries()].map(([id, game]) => {
      const meta = gameMeta.get(id);
      const spectators = gameSpectators.get(id);
      return {
        game_id: id,
        players: game.players,
        result: !!meta?.result,
        disconnected: meta?.disconnected ? [...meta.disconnected] : [],
        spectators: spectators ? spectators.size : 0,
      };
    });
  }

  function playersList() {
    return Array.from(wsByUser.keys());
  }

  function playersStatuses() {
    const all = new Set(playersList());
    for (const [, g] of games.entries()) {
      for (const p of g.players) all.add(p);
    }
    const out = {};
    for (const u of all) out[u] = getUserStatus(u);
    return out;
  }

  function broadcastPlayersList() {
    sendLobbyEvent("players_list", {
      players: playersList(),
      statuses: playersStatuses(),
    });
  }

  function broadcastGamesList() {
    sendLobbyEvent("games_list", { games: gamesList() });
  }

  const refreshLobby = createLobbyRefresher({ broadcastPlayersList, broadcastGamesList });

  return {
    gamesList,
    playersList,
    playersStatuses,
    broadcastPlayersList,
    broadcastGamesList,
    refreshLobby,
  };
}
