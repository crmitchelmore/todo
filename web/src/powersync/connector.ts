import type { AbstractPowerSyncDatabase, PowerSyncBackendConnector } from '@powersync/web';
import { config } from '../config';
import { getToken, clearSession } from '../lib/auth';
import { captureException, startSpan, wideEvent } from '../observability';

const BACKEND_URL = config.backendUrl;
const POWERSYNC_URL = config.powersyncUrl;

/** Bearer header carrying the opaque session token (omitted when signed out). */
function authHeaders(): Record<string, string> {
  const token = getToken();
  return token ? { Authorization: `Bearer ${token}` } : {};
}

/**
 * Connects the local-first SQLite DB to our self-hosted PowerSync + backend.
 * - fetchCredentials: short-lived JWT minted by the backend.
 * - uploadData: drains the local write queue and applies it to Postgres via the backend.
 * Writes are always local-first and instant; this runs in the background.
 */
export class BackendConnector implements PowerSyncBackendConnector {
  async fetchCredentials() {
    return startSpan('Fetch PowerSync credentials', 'sync.credentials', async () => {
      try {
        const res = await fetch(`${BACKEND_URL}/api/auth/token`, { headers: authHeaders() });
        if (res.status === 401) {
          clearSession();
          throw new Error('session expired');
        }
        if (!res.ok) throw new Error(`auth token request failed: ${res.status}`);
        const { token, powersync_url } = await res.json();
        wideEvent('web.sync.credentials', { status: 'ok' });
        return { endpoint: POWERSYNC_URL || powersync_url, token };
      } catch (error) {
        captureException(error, { op: 'web_fetch_powersync_credentials' });
        wideEvent('web.sync.credentials', { status: 'error', error_type: error instanceof Error ? error.name : typeof error });
        throw error;
      }
    });
  }

  async uploadData(database: AbstractPowerSyncDatabase): Promise<void> {
    const tx = await database.getNextCrudTransaction();
    if (!tx) return;
    const started = performance.now();

    const ops = tx.crud.map((entry) => ({
      op: entry.op,
      type: entry.table,
      id: entry.id,
      data: entry.opData
    }));

    await startSpan('Upload PowerSync data', 'sync.upload', async () => {
      try {
        const res = await fetch(`${BACKEND_URL}/api/data`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json', ...authHeaders() },
          body: JSON.stringify({ ops })
        });
        if (res.status === 401) {
          clearSession();
          throw new Error('session expired');
        }
        if (!res.ok) throw new Error(`upload failed: ${res.status} ${await res.text()}`);

        await tx.complete();
        wideEvent('web.sync.upload', {
          status: 'ok',
          op_count: ops.length,
          tables: [...new Set(ops.map((op) => op.type))],
          duration_ms: Math.round(performance.now() - started),
        });
      } catch (error) {
        captureException(error, { op: 'web_sync_upload', op_count: ops.length, tables: [...new Set(ops.map((op) => op.type))] });
        wideEvent('web.sync.upload', {
          status: 'error',
          op_count: ops.length,
          tables: [...new Set(ops.map((op) => op.type))],
          duration_ms: Math.round(performance.now() - started),
          error_type: error instanceof Error ? error.name : typeof error,
        });
        throw error;
      }
    });
  }
}
