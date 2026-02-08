import fs from "fs";
import path from "path";
import os from "os";

import {
  loadUsers,
  saveUsers,
  verifyOrCreateUser,
  setUsersFileForTests
} from "../../domain/auth/usersStore.js";

const TEMP_DIR = fs.mkdtempSync(path.join(os.tmpdir(), "usersStoreTest-"));
const TEST_FILE = path.join(TEMP_DIR, "Users.json");

setUsersFileForTests(TEST_FILE);

describe("usersStore sécurisé", () => {
  beforeEach(() => {
    if (fs.existsSync(TEST_FILE)) fs.unlinkSync(TEST_FILE);
  });

  afterAll(() => {
    if (fs.existsSync(TEST_FILE)) fs.unlinkSync(TEST_FILE);
    fs.rmSync(TEMP_DIR, { recursive: true, force: true });
  });

  test("loadUsers crée un fichier vide si inexistant", () => {
    const users = loadUsers();
    expect(users).toEqual({ players: [] });
    expect(fs.existsSync(TEST_FILE)).toBe(true);
  });

  test("verifyOrCreateUser crée un nouvel utilisateur", async () => {
    const result = await verifyOrCreateUser("testuser", "1234");
    expect(result).toBe(true);

    const data = JSON.parse(fs.readFileSync(TEST_FILE, "utf8"));
    expect(data.players.some(u => u.user === "testuser")).toBe(true);
  });

  test("verifyOrCreateUser vérifie un utilisateur existant", async () => {
    await verifyOrCreateUser("testuser", "1234");
    const result = await verifyOrCreateUser("testuser", "1234");
    expect(result).toBe(true);
  });
});
