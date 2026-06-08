import { config } from '../config';
import { getSession, getToken, ownerId } from './auth';
import { db } from '../powersync/db';

export interface SyncTaskCounts {
  total: number;
  proposed: number;
  active: number;
  done: number;
  cancelled: number;
  by_status: Record<string, number>;
  last_updated_at: string | null;
}

export interface ServerSyncDiagnostics {
  ok: boolean;
  owner: { id: string; email: string | null; created_at: string | null };
  endpoints: { backend_url: string; powersync_url: string };
  server_counts: SyncTaskCounts;
  current_session: {
    client: string | null;
    created_at: string;
    last_seen_at: string | null;
    expires_at: string;
    revoked_at: string | null;
  } | null;
  sessions: Array<{
    client: string;
    sessions: number;
    active_sessions: number;
    newest_seen_at: string | null;
  }>;
}

export interface LocalSyncDiagnostics {
  owner_id: string | null;
  session_owner_id: string | null;
  endpoints: { backend_url: string; powersync_url: string };
  counts: SyncTaskCounts;
  owner_ids: string[];
}

export interface CombinedSyncDiagnostics {
  server: ServerSyncDiagnostics;
  local: LocalSyncDiagnostics;
}

export async function fetchServerSyncDiagnostics(): Promise<ServerSyncDiagnostics> {
  const token = getToken();
  if (!token) throw new Error('Not signed in.');
  const res = await fetch(`${config.backendUrl}/api/diagnostics/sync`, {
    headers: { Authorization: `Bearer ${token}` }
  });
  const body = (await res.json().catch(() => ({}))) as Partial<ServerSyncDiagnostics> & { error?: string };
  if (!res.ok || !body.ok) throw new Error(body.error ?? `diagnostics failed (${res.status})`);
  return body as ServerSyncDiagnostics;
}

export async function localSyncDiagnostics(): Promise<LocalSyncDiagnostics> {
  const rows = await db.getAll<{ status: string; count: number; last_updated_at: string | null }>(
    `SELECT status,
            COUNT(*) AS count,
            MAX(updated_at) AS last_updated_at
       FROM tasks
      GROUP BY status
      ORDER BY status`
  );
  const ownerRows = await db.getAll<{ owner_id: string }>(
    `SELECT DISTINCT owner_id
       FROM tasks
      WHERE owner_id IS NOT NULL
      ORDER BY owner_id
      LIMIT 20`
  );
  const byStatus = Object.fromEntries(rows.map((row) => [row.status, Number(row.count)]));
  const lastUpdatedAt = rows
    .map((row) => row.last_updated_at)
    .filter((value): value is string => Boolean(value))
    .sort()
    .at(-1) ?? null;
  return {
    owner_id: ownerId(),
    session_owner_id: getSession()?.userId ?? null,
    endpoints: { backend_url: config.backendUrl, powersync_url: config.powersyncUrl },
    counts: {
      total: rows.reduce((sum, row) => sum + Number(row.count), 0),
      proposed: byStatus.proposed ?? 0,
      active: (byStatus.active ?? 0) + (byStatus.confirmed ?? 0),
      done: byStatus.done ?? 0,
      cancelled: byStatus.cancelled ?? 0,
      by_status: byStatus,
      last_updated_at: lastUpdatedAt
    },
    owner_ids: ownerRows.map((row) => row.owner_id)
  };
}

export async function fetchCombinedSyncDiagnostics(): Promise<CombinedSyncDiagnostics> {
  const [server, local] = await Promise.all([fetchServerSyncDiagnostics(), localSyncDiagnostics()]);
  return { server, local };
}

export function syncDiagnosticIssues(diagnostics: CombinedSyncDiagnostics): string[] {
  const issues: string[] = [];
  if (diagnostics.local.owner_id !== diagnostics.server.owner.id) {
    issues.push('This device is signed into a different owner ID than the server session.');
  }
  const otherLocalOwners = diagnostics.local.owner_ids.filter((id) => id !== diagnostics.server.owner.id);
  if (otherLocalOwners.length > 0) {
    issues.push('Local cache contains rows for another owner. Sign out/in to force a clean reset.');
  }
  if (diagnostics.local.counts.total !== diagnostics.server.server_counts.total) {
    issues.push('Local task count differs from the server; sync may still be catching up or connected to a different endpoint.');
  }
  if (diagnostics.local.endpoints.backend_url !== diagnostics.server.endpoints.backend_url) {
    issues.push('The app is configured for a different backend URL than the authenticated server reports.');
  }
  if (diagnostics.local.endpoints.powersync_url !== diagnostics.server.endpoints.powersync_url) {
    issues.push('The app is configured for a different PowerSync URL than the authenticated server reports.');
  }
  return issues;
}
