import { useEffect, useState } from 'react';
import { AuthSecurity } from './AuthSecurity';
import { applyAppearance, getAppearance, setAppearance, type AppearanceMode } from '../lib/preferences';

const APPEARANCE_OPTIONS: Array<{ value: AppearanceMode; label: string; hint: string }> = [
  { value: 'system', label: 'System', hint: 'Follow this device.' },
  { value: 'dark', label: 'Dark', hint: 'Ink canvas, maximum focus.' },
  { value: 'light', label: 'Light', hint: 'Paper desk for daylight.' },
];

export function SettingsPanel({ onSignOut }: { onSignOut: () => Promise<void> }) {
  const [appearance, setAppearanceState] = useState<AppearanceMode>(() => getAppearance());
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    applyAppearance(appearance);
  }, [appearance]);

  function choose(mode: AppearanceMode) {
    setAppearance(mode);
    setAppearanceState(mode);
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
