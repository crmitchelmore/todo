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

/** Wipe the local DB + upload queue. Called on auth boundaries so accounts never cross-contaminate. */
export async function resetLocalData(): Promise<void> {
  connected = false;
  await db.disconnectAndClear();
}
