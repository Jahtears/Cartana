// Game.js (barrel)
export { createGame, shuffle, findCardById } from "./state.js";
export {
  mapSlotForClient,
  mapSlotFromClientToServer,
  isOwnerForSlot,
  buildCardData,
  emitSlotState,
  emitFullState,
} from "./slots.js";
export { ensureGameMeta, ensureGameResult } from "./meta.js";
export { getTableSlots } from "./SlotManager.js"; 
