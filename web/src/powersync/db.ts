import { PowerSyncDatabase } from '@powersync/web';
import { AppSchema } from './schema';
import { BackendConnector } from './connector';

// Single-user dev identity for M1. The backend overrides owner_id server-side anyway.
export const OWNER_ID = '00000000-0000-0000-0000-000000000001';

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
