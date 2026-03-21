import {
  buildSlotStatePayload,
  buildStateSnapshotPayload,
  publicGameEndResult,
} from '../../game/payload/snapshotPayload.js';

function resolvePlayerOpponent(game, username) {
  if (!game || !Array.isArray(game.players)) {
    return '';
  }
  const players = game.players.filter((p) => typeof p === 'string' && p.trim());
  if (!players.includes(username)) {
    return '';
  }
  return players.find((p) => p !== username) ?? '';
}

function isSocketOpen(ws) {
  return Boolean(ws) && ws.readyState === 1;
}

function isRematchAllowedForPlayer(
  game,
  gameId,
  meta,
  wsByUser,
  userToGame,
  userToEndGame,
  username,
) {
  const opponent = resolvePlayerOpponent(game, username);
  if (!opponent) {
    return false;
  }
  if (!wsByUser || typeof wsByUser.get !== 'function') {
    return false;
  }
  const inSameGame = Boolean(
    userToGame &&
    typeof userToGame.get === 'function' &&
    String(userToGame.get(opponent) ?? '') === String(gameId ?? ''),
  );
  const inSameEndGame = Boolean(
    userToEndGame &&
    typeof userToEndGame.get === 'function' &&
    String(userToEndGame.get(opponent) ?? '') === String(gameId ?? ''),
  );
  if (!inSameGame && !inSameEndGame) {
    return false;
  }
  if (!isSocketOpen(wsByUser.get(opponent))) {
    return false;
  }
  if (meta?.disconnected instanceof Set && meta.disconnected.has(opponent)) {
    return false;
  }
  return true;
}

export function emitSlotState(
  game,
  recipients,
  wsByUser,
  sendEvtSocket,
  { slot_id, view = 'player' },
) {
  if (!wsByUser || typeof wsByUser.get !== 'function') {
    return;
  }

  for (const username of recipients) {
    const ws = wsByUser.get(username);
    if (!ws) {
      continue;
    }

    const payload = buildSlotStatePayload(game, username, slot_id, view);
    sendEvtSocket(ws, 'slot_state', payload);
  }
}

export function emitFullState(
  game,
  username,
  wsByUser,
  sendEvtSocket,
  { view = 'player', gameMeta = null, game_id = '', userToGame = null, userToEndGame = null } = {},
) {
  if (!wsByUser || typeof wsByUser.get !== 'function') {
    return;
  }

  const ws = wsByUser.get(username);
  if (!ws) {
    return;
  }

  let result = null;
  const forceDisableDrag = Boolean(game?.turn?.paused);
  if (gameMeta && game_id) {
    const meta = gameMeta.get(game_id) || {};
    if (meta.result) {
      result = publicGameEndResult(meta.result);
      if (view === 'player') {
        result.rematch_allowed = isRematchAllowedForPlayer(
          game,
          game_id,
          meta,
          wsByUser,
          userToGame,
          userToEndGame,
          username,
        );
      }
    }
  }

  const snapshot = buildStateSnapshotPayload(game, username, view, { result, forceDisableDrag });

  sendEvtSocket(ws, 'state_snapshot', snapshot);
}
