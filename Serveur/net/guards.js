//\game\guards.js 

import { ensureGameMeta } from "../domain/game/meta.js";
import { resBadRequest, resNotFound, resBadState, resForbidden, resGameEnd } from "./transport.js";

function getResponder(ctx) {
  return ctx?.sendRes;
}

export function requireParam(sendRes, ws, req, data, key, label = key) {
  const value = String(data?.[key] ?? "").trim();
  if (!value) {
    resBadRequest(sendRes, ws, req, `${label} manquant`);
    return null;
  }
  return value;
}

export function getExistingGameOrRes(ctx, ws, req, game_id) {
  const { state } = ctx;
  const sendRes = getResponder(ctx);

  if (!game_id || !state.hasGame(game_id)) {
    resNotFound(sendRes, ws, req, "Partie introuvable");
    return null;
  }
  return state.getGame(game_id);
}

/**
 * Pour les handlers où le game_id est issu du mapping joueur.
 */
export function getPlayerGameOrRes(ctx, ws, req, actor) {
  const { state } = ctx;
  const sendRes = getResponder(ctx);

  const game_id = state.getUserGame(actor);
  if (!game_id || !state.hasGame(game_id)) {
    resNotFound(sendRes, ws, req, "Partie introuvable");
    return null;
  }
  return { game_id, game: state.getGame(game_id) };
}

export function getGameIdFromDataOrMapping(
  ctx,
  ws,
  req,
  data,
  actor,
      {
    key = "game_id",
    required = true,
    preferMapping = false,
    allowedKeys = null, // ex: ["game_id"] ou ["game_id","to"]
  } = {}
) {
  const { state } = ctx;
  const sendRes = getResponder(ctx);

    // whitelist des clés acceptées (anti-typo)
  if (Array.isArray(allowedKeys) && allowedKeys.length) {
    if (!allowedKeys.includes(key)) {
      if (required) {
        resBadRequest(sendRes, ws, req, `clé invalide: ${key}`)
      }
      return null;
    }

    // si le client envoie une clé "proche" non autorisée, on renvoie une erreur explicite
    // (évite silence si data contient gameId au lieu de game_id)
    const norm = (s) => String(s).toLowerCase().replace(/_/g, "");
    const expected = norm(key);
    const dataKeys = data && typeof data === "object" ? Object.keys(data) : [];
    for (const k of dataKeys) {
      if (allowedKeys.includes(k)) continue;
      // détecte gameId vs game_id (ou autres variantes équivalentes)
      if (norm(k) === expected) {
        resBadRequest(sendRes, ws, req, `champ inattendu: ${k} (attendu: ${allowedKeys.join(", ")})`);
        return null;
      }
    }
  }
  // data key (optionnel) : on ne force pas l’erreur ici, car fallback mapping possible
  const fromData = String(data?.[key] ?? "").trim();
  const inferred = String(state.getUserGame(actor) ?? state.getUserSpectate(actor) ?? "").trim();

  const game_id = preferMapping ? (inferred || fromData) : (fromData || inferred);

  if (!game_id) {
      if (required) return requireParam(sendRes, ws, req, data, key, key); // génère l’erreur standard

    return null;
  }
  return game_id;
}

export function rejectIfBusyOrRes(ctx, ws, req, username, message = "Tu es déjà en partie") {
  const sendRes = getResponder(ctx);
  const state = ctx?.state;

  const inGame = typeof state?.getUserGame === "function"
    ? !!state.getUserGame(username)
    : !!state?.userToGame?.get?.(username);

  if (inGame) {
    resBadState(sendRes, ws, req, message);
    return true;
  }
  return false;
}

export function rejectIfSpectatorOrRes(ctx, ws, req, game_id, actor, message = "Spectateur: action interdite") {
  const sendRes = getResponder(ctx);
  const state = ctx?.state;

  const spectatingGameId = typeof state?.getUserSpectate === "function"
    ? state.getUserSpectate(actor)
    : state?.userToSpectate?.get?.(actor);

  const sameGameAsSpectator = String(spectatingGameId ?? "") === String(game_id ?? "");

  if (sameGameAsSpectator) {
    resForbidden(sendRes, ws, req, message);
    return true;
  }
  return false;
}

export function rejectIfEndedOrRes(ctx, ws, req, game_id, game) {
  const { state } = ctx;
  const sendRes = getResponder(ctx);
  const meta = ensureGameMeta(state.gameMeta, game_id, { initialSent: !!game?.turn });
  if (meta?.result) {
    resGameEnd(sendRes, ws, req, "Partie terminée");
    return true;
  }
  return false;
}
