import { PowerSyncDatabase } from '@powersync/web';
import { AppSchema } from './schema';
import { BackendConnector } from './connector';
import { ownerId as sessionOwnerId } from '../lib/auth';

/** Owner id for local optimistic writes: the signed-in user (the backend re-asserts it anyway). */
export function ownerId(): string {
  return sessionOwnerId();
}

export const db = new PowerSyncDatabase({
  schema: AppSchema,
  database: { dbFilename: 'capture.db' }
});

let connected = false;
export async function initPowerSync(): Promise<void> {
  if (connected) return;
  connected = true;
  await db.connect(new BackendConnector());
}

/** Wipe the local DB + upload queue. Called on real account boundaries (sign-out, or sign-in as a
 * different user) so accounts never cross-contaminate. */
export async function resetLocalData(): Promise<void> {
  connected = false;
  await db.disconnectAndClear();
}

const LAST_USER_KEY = 'capture.last_user';

/** Prepare local storage for the signed-in user and connect. Only wipes when the account changed
 * since last run — a normal reload with the same session keeps any pending offline writes so they
 * still upload. */
export async function prepareForActiveUser(): Promise<void> {
  const current = ownerId();
  if (localStorage.getItem(LAST_USER_KEY) !== current) {
    await resetLocalData();
    localStorage.setItem(LAST_USER_KEY, current);
  }
  await initPowerSync();
}

/** Clear local data on sign-out so the next account starts clean. */
export async function clearActiveUser(): Promise<void> {
  localStorage.removeItem(LAST_USER_KEY);
  await resetLocalData();
}
