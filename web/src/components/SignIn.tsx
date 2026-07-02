import { useEffect, useState } from 'react';
import {
  signIn,
  register,
  requestEmailCode,
  verifyEmailCode,
  requestPasswordReset,
  resetPassword,
  MfaRequiredError,
  signInWithPasskey,
  signInWithGitHub,
  oauthProviders,
  verifyMfaLogin,
} from '../lib/auth';

/** Top-level auth views: password tabs, passwordless email-code, or forgot-password reset. */
type View = 'password' | 'code' | 'forgot';
type Mode = 'signIn' | 'register';

/** Auth gate shown before the capture UI. Email + password, passwordless code, or password reset. */
export function SignIn({ initialError, onSignedIn }: { initialError?: string | null; onSignedIn: () => void }) {
  const [view, setView] = useState<View>('password');
  const [mode, setMode] = useState<Mode>('signIn');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [code, setCode] = useState('');
  const [sent, setSent] = useState(false); // second phase of code / forgot flows
  const [error, setError] = useState<string | null>(initialError ?? null);
  const [note, setNote] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [mfaChallenge, setMfaChallenge] = useState<string | null>(null);
  const [githubAvailable, setGithubAvailable] = useState(false);
  const [cooldown, setCooldown] = useState(0); // seconds until a code can be resent (0 = ready)

  useEffect(() => {
    if (cooldown <= 0) return;
    const t = setInterval(() => setCooldown((c) => Math.max(0, c - 1)), 1000);
    return () => clearInterval(t);
  }, [cooldown]);

  useEffect(() => {
    let active = true;
    void oauthProviders()
      .then((providers) => { if (active) setGithubAvailable(providers.github); })
      .catch(() => { if (active) setGithubAvailable(false); });
    return () => { active = false; };
  }, []);

  function go(next: View) {
    setView(next);
    setSent(false);
    setCode('');
    setPassword('');
    setError(null);
    setNote(null);
    setCooldown(0);
  }

  async function run(fn: () => Promise<void>, after?: () => void) {
    setBusy(true);
    setError(null);
    try {
      await fn();
      after?.();
    } catch (err) {
      if (err instanceof MfaRequiredError) {
        setMfaChallenge(err.challenge);
        setNote('Enter the 6-digit code from your authenticator app, or a recovery code.');
        return;
      }
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
  function handleMfa(e: React.FormEvent) {
    e.preventDefault();
    if (!mfaChallenge) return;
    if (!code.trim()) return setError('Enter your authentication code.');
    run(() => verifyMfaLogin(mfaChallenge, code), onSignedIn);
  }
  function handlePasskey() {
    run(() => signInWithPasskey(email || undefined), onSignedIn);
  }

  // --- passwordless email code ------------------------------------------------------------------
  function handleSendCode(e: React.FormEvent) {
    e.preventDefault();
    if (!email.trim()) return setError('Enter your email.');
    run(() => requestEmailCode(email), () => {
      setSent(true);
      setCooldown(60);
      setNote(`We sent a 6-digit code to ${email.trim()}.`);
    });
  }
  function handleVerifyCode(e: React.FormEvent) {
    e.preventDefault();
    if (!code.trim()) return setError('Enter the code from your email.');
    run(() => verifyEmailCode(email, code), onSignedIn);
  }

  // Re-issue a sign-in / reset code. Available once the 60s cooldown elapses (matches the
  // per-ip+email issuance throttle) so users aren't stranded when an email is slow to arrive.
  function handleResend() {
    if (cooldown > 0 || busy) return;
    const request = view === 'forgot' ? requestPasswordReset : requestEmailCode;
    run(() => request(email), () => {
      setCooldown(60);
      setNote(`A new code is on its way to ${email.trim()}.`);
    });
  }
  const resendButton = (
    <button type="button" className="signin-link" onClick={handleResend} disabled={busy || cooldown > 0}>
      {cooldown > 0 ? `Resend code in ${cooldown}s` : 'Resend code'}
    </button>
  );

  // --- forgot password --------------------------------------------------------------------------
  function handleSendReset(e: React.FormEvent) {
    e.preventDefault();
    if (!email.trim()) return setError('Enter your email.');
    run(() => requestPasswordReset(email), () => {
      setSent(true);
      setCooldown(60);
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
      <div className="signin-card">
        <h1>Capture</h1>
        <p className="signin-sub">Sign in to sync your todos across your devices.</p>

        {mfaChallenge && (
          <form className="signin-form" onSubmit={handleMfa}>
            <input
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              placeholder="Authenticator or recovery code"
              value={code}
              onChange={(e) => setCode(e.target.value)}
              disabled={busy}
            />
            <button className="signin-submit" type="submit" disabled={busy}>
              {busy ? 'Verifying…' : 'Verify & Sign In'}
            </button>
            <button
              type="button"
              className="signin-link"
              onClick={() => { setMfaChallenge(null); setCode(''); setNote(null); }}
            >
              Back to sign-in
            </button>
          </form>
        )}

        {!mfaChallenge && (
          <>
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
            {mode === 'signIn' && (
              <button type="button" className="signin-alt" onClick={handlePasskey} disabled={busy}>
                Sign in with a passkey
              </button>
            )}
            {mode === 'signIn' && githubAvailable && (
              <button type="button" className="signin-alt" onClick={signInWithGitHub} disabled={busy}>
                Sign in with GitHub
              </button>
            )}
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
                {resendButton}
                <button type="button" className="signin-link" onClick={() => { setSent(false); setNote(null); setCooldown(0); }}>
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
                {resendButton}
              </form>
            )}
            <button type="button" className="signin-alt" onClick={() => go('password')}>
              Back to password sign-in
            </button>
          </>
        )}
          </>
        )}

        {note && <p className="signin-note">{note}</p>}
        {error && <p className="signin-error">{error}</p>}
      </div>
    </div>
  );
}
