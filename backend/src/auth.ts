import {
  createRemoteJWKSet,
  jwtVerify,
  exportJWK,
  importPKCS8,
  generateKeyPair,
  type JWK,
  type KeyLike,
} from 'jose';
import { createHash, randomBytes } from 'crypto';
import type pg from 'pg';

/**
 * Capture auth: Sign in with Apple + opaque, revocable sessions.
 *
 * Two distinct credentials, on purpose:
 *  - REST backend (`/api/data`, `/api/capture`, `/api/auth/token`) is gated by an OPAQUE session
 *    token (random; we only persist its SHA-256). Opaque => trivially revocable (logout, Apple
 *    credential revoked, account deletion) and nothing sensitive is self-contained in the token.
 *  - PowerSync still receives a short-lived RS256 JWT minted per request (`aud=powersync`, `sub`
 *    = the user's id), which the PowerSync service verifies via our JWKS. Strict, separate `aud`
 *    keeps the two from being interchangeable.
 */

const APPLE_ISSUER = 'https://appleid.apple.com';
const appleJwks = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));

export interface AppleClaims {
  sub: string;
  email?: string;
}

/**
 * Verify an Apple ID token: signature (Apple JWKS), issuer, exact audience, expiry, and — when a
 * raw nonce is supplied — that its SHA-256 matches the token's `nonce` claim (replay protection;
 * native clients set `request.nonce = sha256(raw)` and send us `raw`).
 */
export async function verifyAppleIdentityToken(
  token: string,
  audiences: string[],
  rawNonce?: string,
  jwks: Parameters<typeof jwtVerify>[1] = appleJwks
): Promise<AppleClaims> {
  const { payload } = await jwtVerify(token, jwks, {
    issuer: APPLE_ISSUER,
    audience: audiences,
    maxTokenAge: '10m',
  });
  if (rawNonce) {
    const expected = createHash('sha256').update(rawNonce).digest('hex');
    if (payload.nonce !== expected) throw new Error('nonce mismatch');
  }
  if (typeof payload.sub !== 'string' || !payload.sub) throw new Error('apple token missing sub');
  const email = typeof payload.email === 'string' ? payload.email : undefined;
  return { sub: payload.sub, email };
}

// --- Opaque session tokens --------------------------------------------------------------------

export function newOpaqueToken(): string {
  return randomBytes(32).toString('base64url');
}

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

export async function createSession(
  pool: pg.Pool,
  userId: string,
  client: string | null,
  ttlDays = 30
): Promise<string> {
  const token = newOpaqueToken();
  const expires = new Date(Date.now() + ttlDays * 86_400_000);
  await pool.query(
    `INSERT INTO public.sessions (user_id, token_hash, client, expires_at)
     VALUES ($1, $2, $3, $4)`,
    [userId, hashToken(token), client, expires]
  );
  return token;
}

/** Resolve an opaque token to its user id, bumping last_seen. Null if missing/expired/revoked. */
export async function lookupSession(pool: pg.Pool, token: string): Promise<string | null> {
  const r = await pool.query(
    `UPDATE public.sessions SET last_seen_at = now()
     WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > now()
     RETURNING user_id`,
    [hashToken(token)]
  );
  return (r.rowCount ?? 0) > 0 ? (r.rows[0].user_id as string) : null;
}

export async function revokeSession(pool: pg.Pool, token: string): Promise<void> {
  await pool.query(
    `UPDATE public.sessions SET revoked_at = now() WHERE token_hash = $1 AND revoked_at IS NULL`,
    [hashToken(token)]
  );
}

/**
 * Map an Apple identity to a stable internal user id, creating the user + identity on first
 * sign-in. Returns the internal `users.id` (which is the row `owner_id` everywhere).
 */
export async function upsertUserForApple(
  pool: pg.Pool,
  sub: string,
  email: string | undefined
): Promise<string> {
  const existing = await pool.query(
    `SELECT user_id FROM public.user_identities WHERE provider = 'apple' AND provider_subject = $1`,
    [sub]
  );
  if ((existing.rowCount ?? 0) > 0) return existing.rows[0].user_id as string;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const u = await client.query(
      `INSERT INTO public.users (email) VALUES ($1) RETURNING id`,
      [email ?? null]
    );
    await client.query(
      `INSERT INTO public.user_identities (user_id, provider, provider_subject, email)
       VALUES ($1, 'apple', $2, $3)
       ON CONFLICT (provider, provider_subject) DO NOTHING`,
      [u.rows[0].id, sub, email ?? null]
    );
    // Re-read to resolve the winner of any concurrent first-login race.
    const resolved = await client.query(
      `SELECT user_id FROM public.user_identities WHERE provider = 'apple' AND provider_subject = $1`,
      [sub]
    );
    await client.query('COMMIT');
    return resolved.rows[0].user_id as string;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

// --- RS256 signing key for PowerSync tokens ---------------------------------------------------

export interface SigningKey {
  privateKey: KeyLike;
  publicJwk: JWK;
  kid: string;
}

/**
 * Load the RS256 signing key. Persisting it (PEM in `BACKEND_JWT_PRIVATE_KEY`) keeps the JWKS
 * stable across restarts so the PowerSync service never rejects in-flight tokens after a deploy.
 * Falls back to an ephemeral key in local dev (with a warning) so there's zero setup to run.
 */
export async function loadSigningKey(): Promise<SigningKey> {
  const kid = process.env.JWT_KID ?? 'capture-key-1';
  const pem = process.env.BACKEND_JWT_PRIVATE_KEY;
  let privateKey: KeyLike;
  if (pem && pem.includes('PRIVATE KEY')) {
    privateKey = await importPKCS8(pem.replace(/\\n/g, "\n"), "RS256");
  } else {
    if (process.env.NODE_ENV === 'production' || process.env.RAILWAY_ENVIRONMENT) {
      console.warn(
        'BACKEND_JWT_PRIVATE_KEY not set — using an ephemeral signing key. ' +
          'PowerSync tokens will be invalidated on every restart. Set a persistent key.'
      );
    }
    privateKey = (await generateKeyPair('RS256', { extractable: true })).privateKey;
  }
  const full = await exportJWK(privateKey);
  // Public JWK only — never expose private fields (d, p, q, dp, dq, qi) in the JWKS.
  const publicJwk: JWK = { kty: full.kty, n: full.n, e: full.e, kid, alg: 'RS256', use: 'sig' };
  return { privateKey, publicJwk, kid };
}
