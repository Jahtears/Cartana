// Serveur/domain/auth/usersStore.js
import fs from "fs";
import bcrypt from "bcrypt";

export let USERS_FILE = "./app/saves/Users.json";   // ← devient exporté
const SALT_ROUNDS = 10;

export function setUsersFileForTests(filePath) {     // ← permet de rediriger en test
  USERS_FILE = filePath;
}

export function loadUsers() {
  if (!fs.existsSync(USERS_FILE)) {
    fs.writeFileSync(USERS_FILE, JSON.stringify({ players: [] }, null, 2));
  }

  try {
    return JSON.parse(fs.readFileSync(USERS_FILE));
  } catch (err) {
    console.error("[USERS] Corrupted Users.json, resetting", err);
    return { players: [] };
  }
}

export function saveUsers(data) {
  fs.writeFileSync(USERS_FILE, JSON.stringify(data, null, 2));
}

export async function verifyOrCreateUser(username, pin) {
  const data = loadUsers();
  const players = data.players;

  const existing = players.find(p => p.user === username);
  if (existing) return await bcrypt.compare(pin, existing.hash);

  const hash = await bcrypt.hash(pin, SALT_ROUNDS);
  players.push({ user: username, hash });
  saveUsers(data);
  return true;
}
