import { useState } from 'react';
import { signIn, register } from '../lib/auth';

type Mode = 'signIn' | 'register';

/** Email + password gate shown before the capture UI when there's no active session. */
export function SignIn({ onSignedIn }: { onSignedIn: () => void }) {
  const [mode, setMode] = useState<Mode>('signIn');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function handle(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (!email.trim() || !password) {
      setError('Enter your email and password.');
      return;
    }
    if (mode === 'register' && password.length < 8) {
      setError('Password must be at least 8 characters.');
      return;
    }
    setBusy(true);
    try {
      if (mode === 'register') await register(email, password);
      else await signIn(email, password);
      onSignedIn();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Sign in failed');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="signin">
      <h1>Capture</h1>
      <p className="signin-sub">Sign in to sync your todos across your devices.</p>

      <div className="signin-tabs" role="tablist">
        <button
          type="button"
          role="tab"
          aria-selected={mode === 'signIn'}
          className={mode === 'signIn' ? 'active' : ''}
          onClick={() => { setMode('signIn'); setError(null); }}
        >
          Sign In
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={mode === 'register'}
          className={mode === 'register' ? 'active' : ''}
          onClick={() => { setMode('register'); setError(null); }}
        >
          Create Account
        </button>
      </div>

      <form className="signin-form" onSubmit={handle}>
        <input
          type="email"
          placeholder="Email"
          autoComplete="username"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          disabled={busy}
        />
        <input
          type="password"
          placeholder="Password"
          autoComplete={mode === 'register' ? 'new-password' : 'current-password'}
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          disabled={busy}
        />
        <button className="signin-submit" type="submit" disabled={busy}>
          {busy ? 'Please wait…' : mode === 'register' ? 'Create Account' : 'Sign In'}
        </button>
      </form>
      {error && <p className="signin-error">{error}</p>}
    </div>
  );
}
