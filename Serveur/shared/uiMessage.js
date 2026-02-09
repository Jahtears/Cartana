import { GAME_MESSAGE } from "./constants.js";

function firstNonEmpty(...values) {
  for (const value of values) {
    const s = String(value ?? "").trim();
    if (s) return s;
  }
  return "";
}

function safeMeta(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value;
}

/**
 * Canonicalise un payload UI:
 * - text: texte affiche
 * - code: categorie semantique (couleur/client behavior)
 * - color: fallback legacy optionnel
 * - meta: donnees optionnelles
 */
export function toUiMessage(input = {}, defaults = {}) {
  const src = input && typeof input === "object" ? input : {};
  const dft = defaults && typeof defaults === "object" ? defaults : {};

  const text = firstNonEmpty(src.text, src.message, src.reason, dft.text);
  const code = firstNonEmpty(src.code, dft.code, GAME_MESSAGE.INFO);
  const color = firstNonEmpty(src.color, dft.color);
  const meta = {
    ...safeMeta(dft.meta),
    ...safeMeta(src.meta),
  };

  const out = { text, code };
  if (color) out.color = color;
  if (Object.keys(meta).length > 0) out.meta = meta;
  return out;
}
