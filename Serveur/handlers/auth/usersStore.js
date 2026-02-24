// Serveur/handlers/auth/usersStore.js
import fs from "fs";
import bcrypt from "bcrypt";

export let USERS_FILE = "./app/saves/Users.json";
const SALT_ROUNDS = 10;

export function setUsersFileForTests(filePath) {
  USERS_FILE = filePath;
}

export function loadUsers() {
  if (!fs.existsSync(USERS_FILE)) {
    fs.writeFileSync(USERS_FILE, JSON.stringify({ players: [] }, null, 2));
  }

  try {
    const parsed = JSON.parse(fs.readFileSync(USERS_FILE, "utf8"));
    if (parsed && Array.isArray(parsed.players)) return parsed;
    return { players: [] };
  } catch (err) {
    console.error("[USERS] Corrupted Users.json, resetting", err);
    return { players: [] };
  }
}

export function saveUsers(data) {
  fs.writeFileSync(USERS_FILE, JSON.stringify(data, null, 2));
}

async function verifyExistingUserPin(existing, pin) {
  const storedHash = String(existing?.hash ?? "");
  if (!storedHash) return false;

  try {
    return await bcrypt.compare(pin, storedHash);
  } catch {
    return false;
  }
}

export async function verifyOrCreateUser(username, pin) {
  const data = loadUsers();
  const players = Array.isArray(data.players) ? data.players : [];
  data.players = players;

  const existing = players.find((p) => p.user === username);
  if (existing) return verifyExistingUserPin(existing, pin);

  const hash = await bcrypt.hash(pin, SALT_ROUNDS);
  players.push({ user: username, hash });
  saveUsers(data);
  return true;
}
