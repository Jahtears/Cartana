// Serveur/handlers/auth/usersStore.js
import argon2 from 'argon2';
import { dbGetAllUsers, dbGetUser, dbInsertUser } from '../../app/db.js';

export function loadUsers() {
  const rows = dbGetAllUsers();
  return { players: rows.map((r) => ({ user: r.user, hash: r.hash })) };
}

export function saveUsers(data) {
  // DB-backed: insert missing users only (no deletes or updates)
  const players = Array.isArray(data.players) ? data.players : [];
  for (const p of players) {
    try {
      const existing = dbGetUser(p.user);
      if (!existing) {
        dbInsertUser(p.user, String(p.hash ?? ''));
      }
    } catch (err) {
      console.warn('[USERS] insert failed for', p?.user, err);
    }
  }
}
async function verifyExistingUserPin(existing, pin) {
  const storedHash = String(existing?.hash ?? '');
  if (!storedHash) {
    return false;
  }

  try {
    return await argon2.verify(storedHash, pin);
  } catch (err) {
    console.warn('[USERS] verifyExistingUserPin failed', err);
    return false;
  }
}

export async function verifyOrCreateUser(username, pin) {
  const existing = dbGetUser(username);
  if (existing) {
    return verifyExistingUserPin(existing, pin);
  }

  const hash = await argon2.hash(pin);
  {
    dbInsertUser(username, hash);
    return true;
  }
}
