// Game.js (barrel)
export { createGame } from './factory/createGame.js';
export { shuffle, getCardById } from './state/cardStore.js';
export { mapSlotForClient, mapSlotFromClientToServer } from './boundary/slotIdMapper.js';
export { isOwnerForSlot, getTableSlots } from './state/slotStore.js';
export { buildCardPayload } from './payload/cardPayload.js';
export { ensureGameMeta, ensureGameResult } from './meta.js';
