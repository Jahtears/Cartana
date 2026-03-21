import { ensureGameMeta, ensureGameResult } from '../../game/meta.js';
import { publicGameEndResult } from '../../game/payload/snapshotPayload.js';
import { emitFullState } from './emitter.js';
import { recordLeaderboardResult } from '../lobby/LeaderList.js';

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

export function createGameNotifier({
  state = null,
  games = state?.games,
  gameMeta = state?.gameMeta,
  gameSpectators = state?.gameSpectators,
  wsByUser = state?.wsByUser,
  userToGame = state?.userToGame,
  userToEndGame = state?.userToEndGame,
  sendEvtSocket,
  sendEvtUser,
}) {
  function emitStartGameToUser(username, game_id, { spectator = false } = {}) {
    const game = games.get(game_id);
    if (!game) {
      return false;
    }

    ensureGameMeta(gameMeta, game_id, { initialSent: Boolean(game.turn) });

    sendEvtUser(username, 'start_game', {
      game_id,
      players: game.players,
      spectator: Boolean(spectator),
    });
    return true;
  }

  function emitSnapshotsToAudience(game_id, { reason = 'snapshot' } = {}) {
    const game = games.get(game_id);
    if (!game) {
      return false;
    }

    const meta = ensureGameMeta(gameMeta, game_id, { initialSent: Boolean(game.turn) });
    meta.snapshotSeq = (meta.snapshotSeq || 0) + 1;
    meta.lastSnapshot = {
      seq: meta.snapshotSeq,
      at: Date.now(),
      reason: String(reason || 'snapshot'),
    };

    if (process.env.DEBUG_TRACE === '1') {
      console.log('[TRACE]', `snapshot#${meta.snapshotSeq}`, {
        game_id,
        reason: meta.lastSnapshot.reason,
        players: game.players?.length ?? 0,
        spectators: gameSpectators.get(game_id)?.size ?? 0,
        initialSent: Boolean(meta.initialSent),
        hasResult: Boolean(meta.result),
      });
    }

    meta.slot_sig = Object.create(null);
    meta.turn_sig = '';
    gameMeta.set(game_id, meta);

    for (const p of game.players) {
      emitFullState(game, p, wsByUser, sendEvtSocket, {
        gameMeta,
        game_id,
        userToGame,
        userToEndGame,
      });
    }

    const specs = gameSpectators.get(game_id);
    if (specs && specs.size) {
      for (const s of specs) {
        emitFullState(game, s, wsByUser, sendEvtSocket, {
          gameMeta,
          game_id,
          userToGame,
          userToEndGame,
        });
      }
    }

    return true;
  }

  function emitGameEndOnce(game_id, patch, { exclude = [] } = {}) {
    const game = games.get(game_id);
    if (!game) {
      return { payload: null, created: false };
    }

    const meta = ensureGameMeta(gameMeta, game_id, { initialSent: true });
    const { result, created } = ensureGameResult(meta, patch);

    const payload = { game_id, ...publicGameEndResult(result) };
    if (!created) {
      return { payload, created: false };
    }

    try {
      recordLeaderboardResult(game.players, result?.winner ?? null);
    } catch (err) {
      console.error('[LEADERBOARD] failed to persist game result', {
        game_id,
        error: err?.message ?? String(err),
      });
    }

    const excludeSet = new Set((exclude || []).filter(Boolean));

    for (const p of game.players) {
      if (excludeSet.has(p)) {
        continue;
      }
      if (userToEndGame && typeof userToEndGame.set === 'function') {
        userToEndGame.set(p, game_id);
      }
      sendEvtUser(p, 'game_end', {
        ...payload,
        rematch_allowed: isRematchAllowedForPlayer(
          game,
          game_id,
          meta,
          wsByUser,
          userToGame,
          userToEndGame,
          p,
        ),
      });
    }

    const specs = gameSpectators.get(game_id);
    if (specs && specs.size) {
      for (const s of specs) {
        if (excludeSet.has(s)) {
          continue;
        }
        sendEvtUser(s, 'game_end', { ...payload, rematch_allowed: false });
      }
    }

    return { payload, created: true };
  }

  return { emitStartGameToUser, emitSnapshotsToAudience, emitGameEndOnce };
}
