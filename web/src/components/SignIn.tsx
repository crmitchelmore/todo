import { useState } from 'react';
import {
  signIn,
  register,
  requestEmailCode,
  verifyEmailCode,
  requestPasswordReset,
  resetPassword,
} from '../lib/auth';

/** Top-level auth views: password tabs, passwordless email-code, or forgot-password reset. */
type View = 'password' | 'code' | 'forgot';
type Mode = 'signIn' | 'register';

/** Auth gate shown before the capture UI. Email + password, passwordless code, or password reset. */
export function SignIn({ onSignedIn }: { onSignedIn: () => void }) {
  const [view, setView] = useState<View>('password');
  const [mode, setMode] = useState<Mode>('signIn');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [code, setCode] = useState('');
  const [sent, setSent] = useState(false); // second phase of code / forgot flows
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  function go(next: View) {
    setView(next);
    setSent(false);
    setCode('');
    setPassword('');
    setError(null);
    setNote(null);
  }

  async function run(fn: () => Promise<void>, after?: () => void) {
    setBusy(true);
    setError(null);
    try {
      await fn();
      after?.();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong');
    } finally {
      setBusy(false);
    }
  }

  // --- email + password -------------------------------------------------------------------------
  function handlePassword(e: React.FormEvent) {
    e.preventDefault();
    if (!email.trim() || !password) return setError('Enter your email and password.');
    if (mode === 'register' && password.length < 8) {
      return setError('Password must be at least 8 characters.');
    }
    run(() => (mode === 'register' ? register(email, password) : signIn(email, password)), onSignedIn);
  }

  // --- passwordless email code ------------------------------------------------------------------
  function handleSendCode(e: React.FormEvent) {
    e.preventDefault();
    if (!email.trim()) return setError('Enter your email.');
    run(() => requestEmailCode(email), () => {
      setSent(true);
      setNote(`We sent a 6-digit code to ${email.trim()}.`);
    });
  }
  function handleVerifyCode(e: React.FormEvent) {
    e.preventDefault();
    if (!code.trim()) return setError('Enter the code from your email.');
    run(() => verifyEmailCode(email, code), onSignedIn);
  }

  // --- forgot password --------------------------------------------------------------------------
  function handleSendReset(e: React.FormEvent) {
    e.preventDefault();
    if (!email.trim()) return setError('Enter your email.');
    run(() => requestPasswordReset(email), () => {
      setSent(true);
      setNote(`If an account exists for ${email.trim()}, a reset code is on its way.`);
    });
  }
  function handleReset(e: React.FormEvent) {
    e.preventDefault();
    if (!code.trim()) return setError('Enter the reset code from your email.');
    if (password.length < 8) return setError('Password must be at least 8 characters.');
    run(() => resetPassword(email, code, password), onSignedIn);
  }

  const emailInput = (
    <input
      type="email"
      placeholder="Email"
      autoComplete="username"
      value={email}
      onChange={(e) => setEmail(e.target.value)}
      disabled={busy}
    />
  );
  const codeInput = (
    <input
      type="text"
      inputMode="numeric"
      autoComplete="one-time-code"
      placeholder="6-digit code"
      value={code}
      onChange={(e) => setCode(e.target.value)}
      disabled={busy}
    />
  );

  return (
    <div className="signin">
      <h1>Capture</h1>
      <p className="signin-sub">Sign in to sync your todos across your devices.</p>

      {view === 'password' && (
        <>
          <div className="signin-tabs" role="tablist">
            <button
              type="button" role="tab" aria-selected={mode === 'signIn'}
              className={mode === 'signIn' ? 'active' : ''}
              onClick={() => { setMode('signIn'); setError(null); }}
            >Sign In</button>
            <button
              type="button" role="tab" aria-selected={mode === 'register'}
              className={mode === 'register' ? 'active' : ''}
              onClick={() => { setMode('register'); setError(null); }}
            >Create Account</button>
          </div>

          <form className="signin-form" onSubmit={handlePassword}>
            {emailInput}
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

          {mode === 'signIn' && (
            <button type="button" className="signin-link" onClick={() => go('forgot')}>
              Forgot password?
            </button>
          )}
          <div className="signin-divider"><span>or</span></div>
          <button type="button" className="signin-alt" onClick={() => go('code')}>
            Email me a sign-in code
          </button>
        </>
      )}

      {view === 'code' && (
        <>
          {!sent ? (
            <form className="signin-form" onSubmit={handleSendCode}>
              {emailInput}
              <button className="signin-submit" type="submit" disabled={busy}>
                {busy ? 'Sending…' : 'Send me a code'}
              </button>
            </form>
          ) : (
            <form className="signin-form" onSubmit={handleVerifyCode}>
              {codeInput}
              <button className="signin-submit" type="submit" disabled={busy}>
                {busy ? 'Verifying…' : 'Sign In'}
              </button>
              <button type="button" className="signin-link" onClick={() => { setSent(false); setNote(null); }}>
                Use a different email
              </button>
            </form>
          )}
          <button type="button" className="signin-alt" onClick={() => go('password')}>
            Back to password sign-in
          </button>
        </>
      )}

      {view === 'forgot' && (
        <>
          {!sent ? (
            <form className="signin-form" onSubmit={handleSendReset}>
              {emailInput}
              <button className="signin-submit" type="submit" disabled={busy}>
                {busy ? 'Sending…' : 'Send reset code'}
              </button>
            </form>
          ) : (
            <form className="signin-form" onSubmit={handleReset}>
              {codeInput}
              <input
                type="password"
                placeholder="New password"
                autoComplete="new-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                disabled={busy}
              />
              <button className="signin-submit" type="submit" disabled={busy}>
                {busy ? 'Resetting…' : 'Reset & Sign In'}
              </button>
            </form>
          )}
          <button type="button" className="signin-alt" onClick={() => go('password')}>
            Back to password sign-in
          </button>
        </>
      )}

      {note && <p className="signin-note">{note}</p>}
      {error && <p className="signin-error">{error}</p>}
    </div>
  );
}
