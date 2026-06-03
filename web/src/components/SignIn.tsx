import { useState } from 'react';
import { signInWithApple } from '../lib/auth';

/** Sign in with Apple gate shown before the capture UI when there's no active session. */
export function SignIn({ onSignedIn }: { onSignedIn: () => void }) {
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function handle() {
    setError(null);
    setBusy(true);
    try {
      await signInWithApple();
      onSignedIn();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Sign in failed');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="signin">
      <h1>Capture</h1>
      <p className="signin-sub">Sign in to sync your todos across your devices.</p>
      <button className="apple-signin" onClick={handle} disabled={busy}>
        {busy ? 'Signing in…' : ' Sign in with Apple'}
      </button>
      {error && <p className="signin-error">{error}</p>}
    </div>
  );
}
