import { useState } from 'react';
import {
  beginTotpSetup,
  disableTotp,
  registerPasskey,
  rotateRecoveryCodes,
  verifyTotpSetup,
} from '../lib/auth';

export function AuthSecurity() {
  const [busy, setBusy] = useState(false);
  const [code, setCode] = useState('');
  const [secret, setSecret] = useState<string | null>(null);
  const [otpauthUri, setOtpauthUri] = useState<string | null>(null);
  const [recoveryCodes, setRecoveryCodes] = useState<string[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function run(fn: () => Promise<void>) {
    setBusy(true);
    setError(null);
    setMessage(null);
    try {
      await fn();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Security action failed.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="security-panel">
      <h2>Account security</h2>
      <div className="security-grid">
        <div className="security-card">
          <span className="security-kicker">Passkey</span>
          <h3>Device-native sign-in</h3>
          <p>Register this browser with WebAuthn so future sign-ins can use a passkey.</p>
          <button
            type="button"
            className="signin-alt"
            disabled={busy}
            onClick={() => run(async () => {
              await registerPasskey();
              setMessage('Passkey registered for this account.');
            })}
          >
            Add passkey
          </button>
        </div>

        <div className="security-card">
          <span className="security-kicker">2FA</span>
          <h3>Authenticator app</h3>
          <p>Enable TOTP for password sign-ins. Recovery codes are shown once after verification.</p>
          {!secret ? (
            <button
              type="button"
              className="signin-alt"
              disabled={busy}
              onClick={() => run(async () => {
                const setup = await beginTotpSetup();
                setSecret(setup.secret);
                setOtpauthUri(setup.otpauthUri);
              })}
            >
              Set up authenticator
            </button>
          ) : (
            <form
              className="security-form"
              onSubmit={(e) => {
                e.preventDefault();
                void run(async () => {
                  const codes = await verifyTotpSetup(code);
                  setRecoveryCodes(codes);
                  setSecret(null);
                  setOtpauthUri(null);
                  setCode('');
                  setMessage('2FA enabled. Save your recovery codes now.');
                });
              }}
            >
              <div className="security-secret">
                <strong>{secret}</strong>
                {otpauthUri && <small>{otpauthUri}</small>}
              </div>
              <input
                type="text"
                inputMode="numeric"
                autoComplete="one-time-code"
                placeholder="6-digit code"
                value={code}
                onChange={(e) => setCode(e.target.value)}
                disabled={busy}
              />
              <button className="signin-submit" type="submit" disabled={busy}>
                Verify & enable
              </button>
            </form>
          )}

          <form
            className="security-form"
            onSubmit={(e) => {
              e.preventDefault();
              void run(async () => {
                const codes = await rotateRecoveryCodes(code);
                setRecoveryCodes(codes);
                setCode('');
                setMessage('Recovery codes rotated. Save the new codes now.');
              });
            }}
          >
            <input
              type="text"
              placeholder="Authenticator or recovery code"
              value={code}
              onChange={(e) => setCode(e.target.value)}
              disabled={busy}
            />
            <button className="signin-alt" type="submit" disabled={busy}>Rotate recovery codes</button>
            <button
              className="signin-link"
              type="button"
              disabled={busy}
              onClick={() => run(async () => {
                await disableTotp(code);
                setCode('');
                setRecoveryCodes([]);
                setMessage('2FA disabled.');
              })}
            >
              Disable 2FA
            </button>
          </form>
        </div>
      </div>
      {recoveryCodes.length > 0 && (
        <div className="recovery-codes" aria-live="polite">
          {recoveryCodes.map((recoveryCode) => <code key={recoveryCode}>{recoveryCode}</code>)}
        </div>
      )}
      {message && <p className="signin-note">{message}</p>}
      {error && <p className="signin-error">{error}</p>}
    </section>
  );
}
