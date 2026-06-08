import { useEffect, useState } from 'react';
import { AuthSecurity } from './AuthSecurity';
import {
  fetchCombinedSyncDiagnostics,
  syncDiagnosticIssues,
  type CombinedSyncDiagnostics
} from '../lib/diagnostics';
import { applyAppearance, getAppearance, setAppearance, type AppearanceMode } from '../lib/preferences';

const APPEARANCE_OPTIONS: Array<{ value: AppearanceMode; label: string; hint: string }> = [
  { value: 'system', label: 'System', hint: 'Follow this device.' },
  { value: 'dark', label: 'Dark', hint: 'Ink canvas, maximum focus.' },
  { value: 'light', label: 'Light', hint: 'Paper desk for daylight.' },
];

export function SettingsPanel({ onSignOut }: { onSignOut: () => Promise<void> }) {
  const [appearance, setAppearanceState] = useState<AppearanceMode>(() => getAppearance());
  const [busy, setBusy] = useState(false);
  const [diagnostics, setDiagnostics] = useState<CombinedSyncDiagnostics | null>(null);
  const [diagnosticsBusy, setDiagnosticsBusy] = useState(false);
  const [diagnosticsError, setDiagnosticsError] = useState<string | null>(null);

  useEffect(() => {
    applyAppearance(appearance);
  }, [appearance]);

  useEffect(() => {
    void loadDiagnostics();
  }, []);

  function choose(mode: AppearanceMode) {
    setAppearance(mode);
    setAppearanceState(mode);
  }

  async function loadDiagnostics() {
    setDiagnosticsBusy(true);
    setDiagnosticsError(null);
    try {
      setDiagnostics(await fetchCombinedSyncDiagnostics());
    } catch (error) {
      setDiagnosticsError(error instanceof Error ? error.message : 'Diagnostics failed.');
    } finally {
      setDiagnosticsBusy(false);
    }
  }

  async function signOut() {
    setBusy(true);
    try {
      await onSignOut();
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="settings-panel">
      <div className="settings-head">
        <span className="security-kicker">Preferences</span>
        <h2>Settings</h2>
        <p>Keep the command surface fast while tuning the way Capture sits in your day.</p>
      </div>

      <div className="settings-card">
        <h3>Appearance</h3>
        <div className="appearance-grid">
          {APPEARANCE_OPTIONS.map((option) => (
            <button
              key={option.value}
              type="button"
              className={`appearance-choice ${appearance === option.value ? 'selected' : ''}`}
              onClick={() => choose(option.value)}
            >
              <strong>{option.label}</strong>
              <span>{option.hint}</span>
            </button>
          ))}
        </div>
      </div>

      <SyncDiagnosticsCard
        diagnostics={diagnostics}
        error={diagnosticsError}
        busy={diagnosticsBusy}
        onRefresh={() => void loadDiagnostics()}
      />

      <div className="settings-card settings-account">
        <div>
          <h3>Account</h3>
          <p>Password changes use the emailed reset flow from the sign-in screen.</p>
        </div>
        <button className="signin-alt danger-action" type="button" disabled={busy} onClick={() => void signOut()}>
          Sign out
        </button>
      </div>

      <AuthSecurity />
    </section>
  );
}

function SyncDiagnosticsCard({
  diagnostics,
  error,
  busy,
  onRefresh
}: {
  diagnostics: CombinedSyncDiagnostics | null;
  error: string | null;
  busy: boolean;
  onRefresh: () => void;
}) {
  const issues = diagnostics ? syncDiagnosticIssues(diagnostics) : [];
  return (
    <div className="settings-card sync-diagnostics-card">
      <div className="settings-card-title">
        <div>
          <h3>Sync diagnostics</h3>
          <p>Confirm this web session, the local cache and Railway are looking at the same account.</p>
        </div>
        <button className="signin-alt" type="button" disabled={busy} onClick={onRefresh}>
          {busy ? 'Checking…' : 'Refresh'}
        </button>
      </div>
      {error ? <p className="diagnostic-error">{error}</p> : null}
      {diagnostics ? (
        <>
          <div className={`diagnostic-banner ${issues.length ? 'warning' : 'ok'}`}>
            {issues.length ? issues[0] : 'Web local cache and server diagnostics agree.'}
          </div>
          <div className="diagnostic-grid">
            <DiagnosticMetric label="Account" value={diagnostics.server.owner.email ?? diagnostics.server.owner.id} />
            <DiagnosticMetric label="Server total" value={String(diagnostics.server.server_counts.total)} />
            <DiagnosticMetric label="Local total" value={String(diagnostics.local.counts.total)} />
            <DiagnosticMetric label="Session" value={diagnostics.server.current_session?.client ?? 'unknown'} />
            <DiagnosticMetric label="Server updated" value={formatDate(diagnostics.server.server_counts.last_updated_at)} />
            <DiagnosticMetric label="Local updated" value={formatDate(diagnostics.local.counts.last_updated_at)} />
          </div>
          {issues.length > 1 ? (
            <div className="diagnostic-details">
              {issues.slice(1).map((issue) => (
                <span key={issue}>{issue}</span>
              ))}
            </div>
          ) : null}
          <details className="diagnostic-details">
            <summary>Endpoint and session details</summary>
            <span>Backend: {diagnostics.local.endpoints.backend_url}</span>
            <span>PowerSync: {diagnostics.local.endpoints.powersync_url}</span>
            <span>Owner ID: {diagnostics.server.owner.id}</span>
            <span>Local owners: {diagnostics.local.owner_ids.join(', ') || 'none'}</span>
            <span>
              Other clients:{' '}
              {diagnostics.server.sessions
                .map((session) => `${session.client} ${session.active_sessions}/${session.sessions}`)
                .join(', ') || 'none'}
            </span>
          </details>
        </>
      ) : (
        <p>{busy ? 'Checking current sync state…' : 'Diagnostics have not been loaded yet.'}</p>
      )}
    </div>
  );
}

function DiagnosticMetric({ label, value }: { label: string; value: string }) {
  return (
    <div className="diagnostic-metric">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function formatDate(value: string | null): string {
  if (!value) return 'none';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat(undefined, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  }).format(date);
}
