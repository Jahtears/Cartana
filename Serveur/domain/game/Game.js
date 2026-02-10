// Game.js (barrel)
export { createGame, shuffle, findCardById } from "./state.js";
export {
  mapSlotForClient,
  mapSlotFromClientToServer,
  isOwnerForSlot,
  buildCardData,
} from "./slots.js";
export { ensureGameMeta, ensureGameResult } from "./meta.js";
export { getTableSlots } from "./SlotManager.js"; 
