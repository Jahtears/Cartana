const GAME_DEBUG = process.env.DEBUG_TRACE === "1" || process.env.GAME_DEBUG === "1";

function debugLog(...args) {
  if (!GAME_DEBUG) return;
  console.log(...args);
}

function debugWarn(...args) {
  if (!GAME_DEBUG) return;
  console.warn(...args);
}

export {
  GAME_DEBUG,
  debugLog,
  debugWarn,
};
