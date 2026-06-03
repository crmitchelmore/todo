import { config } from '../config';

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

/** Clear the local session (called on sign-out and when the backend rejects our token with 401). */
export function clearSession(): void {
  localStorage.removeItem(STORAGE_KEY);
  emit();
}

interface AuthResponse {
  ok?: boolean;
  session_token?: string;
  user_id?: string;
  error?: string;
}

async function authenticate(path: string, email: string, password: string): Promise<void> {
  const res = await fetch(`${config.backendUrl}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: email.trim(), password, client: 'web' })
  });
  const body: AuthResponse = await res.json().catch(() => ({}));
  if (!res.ok || !body.ok || !body.session_token || !body.user_id) {
    throw new Error(body.error ?? `request failed (${res.status})`);
  }
  setSession({ token: body.session_token, userId: body.user_id });
}

/** Sign in to an existing account with an email + password. */
export async function signIn(email: string, password: string): Promise<void> {
  await authenticate('/api/auth/login', email, password);
}

/** Create a new account with an email + password. */
export async function register(email: string, password: string): Promise<void> {
  await authenticate('/api/auth/register', email, password);
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
