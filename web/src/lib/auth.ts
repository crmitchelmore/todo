import { config } from '../config';

/**
 * Web authentication: Sign in with Apple (JS) exchanged for an opaque backend session token.
 *
 * The session ({ token, userId }) is persisted in localStorage and sent as a Bearer token on every
 * backend call. `userId` is stamped as `owner_id` on local optimistic writes so they line up with
 * the server's owner-scoped writes and the per-user sync filter.
 *
 * NOTE: the Apple JS popup requires an Apple **Services ID** (`VITE_APPLE_SERVICES_ID`) and a
 * verified HTTPS domain + return URL registered in the Apple Developer portal. It therefore only
 * works once the web app is hosted on a real domain — it cannot run from a local `vite dev` origin.
 */

export interface Session {
  token: string;
  userId: string;
}

const STORAGE_KEY = 'capture.session';
const APPLE_JS = 'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js';

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

// --- Apple JS loading ---------------------------------------------------------------------------

let applePromise: Promise<void> | null = null;

function loadAppleJS(): Promise<void> {
  if (applePromise) return applePromise;
  applePromise = new Promise<void>((resolve, reject) => {
    if (document.querySelector(`script[src="${APPLE_JS}"]`)) return resolve();
    const script = document.createElement('script');
    script.src = APPLE_JS;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error('failed to load Apple JS'));
    document.head.appendChild(script);
  });
  return applePromise;
}

function randomNonce(): string {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes)).replace(/[^a-zA-Z0-9]/g, '').slice(0, 32);
}

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

interface AppleAuthResponse {
  authorization: { id_token: string; code: string; state?: string };
}

/**
 * Run the Apple JS popup sign-in, exchange the identity token for a backend session, and persist
 * it. The raw nonce is sent to the backend, which checks `sha256(rawNonce)` against the token's
 * `nonce` claim (the Apple request was initialised with the hashed nonce).
 */
export async function signInWithApple(): Promise<void> {
  const servicesId = import.meta.env.VITE_APPLE_SERVICES_ID;
  if (!servicesId) throw new Error('VITE_APPLE_SERVICES_ID is not configured');

  await loadAppleJS();
  const rawNonce = randomNonce();
  const hashedNonce = await sha256Hex(rawNonce);

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const AppleID = (window as any).AppleID;
  AppleID.auth.init({
    clientId: servicesId,
    scope: 'email',
    redirectURI: import.meta.env.VITE_APPLE_REDIRECT_URI ?? window.location.origin,
    state: randomNonce(),
    nonce: hashedNonce,
    usePopup: true
  });

  const result: AppleAuthResponse = await AppleID.auth.signIn();
  const idToken = result.authorization?.id_token;
  if (!idToken) throw new Error('no identity token from Apple');

  const res = await fetch(`${config.backendUrl}/api/auth/apple`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ identity_token: idToken, nonce: rawNonce, client: 'web' })
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body.ok || !body.session_token || !body.user_id) {
    throw new Error(body.error ?? `sign-in failed (${res.status})`);
  }
  setSession({ token: body.session_token, userId: body.user_id });
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
