import { config } from '../config';
import { startAuthentication, startRegistration } from '@simplewebauthn/browser';

/**
 * Web authentication: email + password exchanged for an opaque backend session token.
 *
 * The session ({ token, userId }) is persisted in localStorage and sent as a Bearer token on every
 * backend call. `userId` is stamped as `owner_id` on local optimistic writes so they line up with
 * the server's owner-scoped writes and the per-user sync filter. Using the same email + password
 * on every surface resolves to the same backend user, so todos sync across web, iOS and macOS.
 */

export interface Session {
  token: string;
  userId: string;
}

const STORAGE_KEY = 'capture.session';

const listeners = new Set<() => void>();

export function onAuthChange(fn: () => void): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

function emit(): void {
  for (const fn of listeners) fn();
}

export function getSession(): Session | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Session;
    return parsed.token && parsed.userId ? parsed : null;
  } catch {
    return null;
  }
}

export function getToken(): string | null {
  return getSession()?.token ?? null;
}

export function isAuthenticated(): boolean {
  return getSession() !== null;
}

/** The owner id to stamp on local writes; falls back to a placeholder when signed out. */
export function ownerId(): string {
  return getSession()?.userId ?? '00000000-0000-0000-0000-000000000000';
}

function setSession(session: Session): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(session));
  emit();
}

export function consumeOAuthSessionFromUrl(): { signedIn: boolean; error: string | null } {
  const hash = window.location.hash.startsWith('#') ? window.location.hash.slice(1) : window.location.hash;
  const params = new URLSearchParams(hash);
  if (params.get('capture_oauth') !== '1') return { signedIn: false, error: null };
  const token = params.get('session_token');
  const userId = params.get('user_id');
  const error = params.get('error');
  window.history.replaceState(null, '', `${window.location.pathname}${window.location.search}`);
  if (token && userId) {
    setSession({ token, userId });
    return { signedIn: true, error: null };
  }
  return { signedIn: false, error: oauthErrorMessage(error) };
}

function oauthErrorMessage(code: string | null): string {
  if (code === 'github_email_needs_linking') {
    return 'That GitHub email already has a Capture account. Sign in with email first; account linking is coming next.';
  }
  if (code === 'github_verified_email_required') {
    return 'GitHub did not return a verified email address for this account.';
  }
  if (code === 'github_not_configured') {
    return 'GitHub sign-in is not fully configured yet.';
  }
  return 'GitHub sign-in did not complete.';
}

/** Clear the local session (called on sign-out and when the backend rejects our token with 401). */
export function clearSession(): void {
  localStorage.removeItem(STORAGE_KEY);
  emit();
}

interface AuthResponse {
  ok?: boolean;
  session_token?: string;
  user_id?: string;
  mfa_required?: boolean;
  mfa_challenge?: string;
  options?: unknown;
  secret?: string;
  otpauth_uri?: string;
  recovery_codes?: string[];
  error?: string;
}

interface OAuthProvidersResponse {
  ok?: boolean;
  github?: { configured?: boolean };
}

export class MfaRequiredError extends Error {
  constructor(readonly challenge: string) {
    super('Enter your authentication code.');
    this.name = 'MfaRequiredError';
  }
}

async function authenticate(path: string, email: string, password: string): Promise<void> {
  const res = await fetch(`${config.backendUrl}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: email.trim(), password, client: 'web' })
  });
  const body: AuthResponse = await res.json().catch(() => ({}));
  if (res.ok && body.ok && body.mfa_required && body.mfa_challenge) {
    throw new MfaRequiredError(body.mfa_challenge);
  }
  if (!res.ok || !body.ok || !body.session_token || !body.user_id) {
    throw new Error(body.error ?? `request failed (${res.status})`);
  }
  setSession({ token: body.session_token, userId: body.user_id });
}

/** Sign in to an existing account with an email + password. */
export async function signIn(email: string, password: string): Promise<void> {
  await authenticate('/api/auth/login', email, password);
}

export async function verifyMfaLogin(challenge: string, code: string): Promise<void> {
  await postSession('/api/auth/login/mfa', { mfa_challenge: challenge, code: code.trim() });
}

/** Create a new account with an email + password. */
export async function register(email: string, password: string): Promise<void> {
  await authenticate('/api/auth/register', email, password);
}

/** Helper for the always-200 issuance endpoints (email-code request, forgot-password request). */
async function postJson(path: string, payload: Record<string, unknown>): Promise<void> {
  const res = await fetch(`${config.backendUrl}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  });
  if (!res.ok) {
    const body: AuthResponse = await res.json().catch(() => ({}));
    throw new Error(body.error ?? `request failed (${res.status})`);
  }
}

/** Helper for endpoints that return a session ({ session_token, user_id }) and sign the user in. */
async function postSession(path: string, payload: Record<string, unknown>): Promise<void> {
  const res = await fetch(`${config.backendUrl}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ...payload, client: 'web' })
  });
  const body: AuthResponse = await res.json().catch(() => ({}));
  if (res.ok && body.ok && body.mfa_required && body.mfa_challenge) {
    throw new MfaRequiredError(body.mfa_challenge);
  }
  if (!res.ok || !body.ok || !body.session_token || !body.user_id) {
    throw new Error(body.error ?? `request failed (${res.status})`);
  }
  setSession({ token: body.session_token, userId: body.user_id });
}

/** Passwordless sign-in, step 1: ask the backend to email a one-time code. */
export async function requestEmailCode(email: string): Promise<void> {
  await postJson('/api/auth/email-code', { email: email.trim() });
}

/** Passwordless sign-in, step 2: exchange the emailed code for a session. */
export async function verifyEmailCode(email: string, code: string): Promise<void> {
  await postSession('/api/auth/email-code/verify', { email: email.trim(), code: code.trim() });
}

/** Forgot password, step 1: ask the backend to email a reset code (always succeeds — no enumeration). */
export async function requestPasswordReset(email: string): Promise<void> {
  await postJson('/api/auth/forgot', { email: email.trim() });
}

/** Forgot password, step 2: set a new password with the emailed code; signs the user in on success. */
export async function resetPassword(email: string, code: string, password: string): Promise<void> {
  await postSession('/api/auth/reset', { email: email.trim(), code: code.trim(), password });
}

async function authedPost(path: string, payload: Record<string, unknown> = {}): Promise<AuthResponse> {
  const token = getToken();
  if (!token) throw new Error('Not signed in.');
  const res = await fetch(`${config.backendUrl}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify(payload)
  });
  const body: AuthResponse = await res.json().catch(() => ({}));
  if (!res.ok || !body.ok) throw new Error(body.error ?? `request failed (${res.status})`);
  return body;
}

export async function beginTotpSetup(): Promise<{ secret: string; otpauthUri: string }> {
  const body = await authedPost('/api/auth/totp/setup');
  if (!body.secret || !body.otpauth_uri) throw new Error('TOTP setup response was incomplete.');
  return { secret: body.secret, otpauthUri: body.otpauth_uri };
}

export async function verifyTotpSetup(code: string): Promise<string[]> {
  const body = await authedPost('/api/auth/totp/verify', { code: code.trim() });
  return body.recovery_codes ?? [];
}

export async function disableTotp(code: string): Promise<void> {
  await authedPost('/api/auth/totp/disable', { code: code.trim() });
}

export async function rotateRecoveryCodes(code: string): Promise<string[]> {
  const body = await authedPost('/api/auth/recovery-codes/rotate', { code: code.trim() });
  return body.recovery_codes ?? [];
}

export async function registerPasskey(): Promise<void> {
  const optionsBody = await authedPost('/api/auth/passkeys/register/options');
  if (!optionsBody.options) throw new Error('Passkey setup response was incomplete.');
  const response = await startRegistration({ optionsJSON: optionsBody.options as never });
  await authedPost('/api/auth/passkeys/register/verify', { response });
}

export async function signInWithPasskey(email?: string): Promise<void> {
  const res = await fetch(`${config.backendUrl}/api/auth/passkeys/login/options`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: email?.trim() ?? '' })
  });
  const optionsBody: AuthResponse = await res.json().catch(() => ({}));
  if (!res.ok || !optionsBody.ok || !optionsBody.options) {
    throw new Error(optionsBody.error ?? `request failed (${res.status})`);
  }
  const response = await startAuthentication({ optionsJSON: optionsBody.options as never });
  await postSession('/api/auth/passkeys/login/verify', { response });
}

export async function oauthProviders(): Promise<{ github: boolean }> {
  const res = await fetch(`${config.backendUrl}/api/auth/oauth/providers`);
  const body: OAuthProvidersResponse = await res.json().catch(() => ({}));
  return { github: Boolean(res.ok && body.ok && body.github?.configured) };
}

export function signInWithGitHub(): void {
  window.location.assign(`${config.backendUrl}/api/auth/oauth/github/start`);
}

/** Best-effort server revoke, then drop the local session regardless of the network result. */
export async function signOut(): Promise<void> {
  const token = getToken();
  if (token) {
    try {
      await fetch(`${config.backendUrl}/api/auth/logout`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}` }
      });
    } catch {
      // ignore network errors — we always clear locally
    }
  }
  clearSession();
}
