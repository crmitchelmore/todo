import {
  exportJWK,
  importPKCS8,
  generateKeyPair,
  type JWK,
  type KeyLike,
} from 'jose';
import { createHash, randomBytes } from 'crypto';
import bcrypt from 'bcryptjs';
import type pg from 'pg';

/**
 * Capture auth: email + password credentials on top of opaque, revocable sessions.
 *
 * Two distinct credentials, on purpose:
 *  - The REST backend (`/api/data`, `/api/capture`, `/api/auth/token`) is gated by an OPAQUE
 *    session token (random; we only persist its SHA-256). Opaque => trivially revocable (logout,
 *    account deletion) and nothing sensitive is self-contained in the token.
 *  - PowerSync still receives a short-lived RS256 JWT minted per request (`aud=powersync`, `sub`
 *    = the user's id), which the PowerSync service verifies via our JWKS. Strict, separate `aud`
 *    keeps the two from being interchangeable.
 *
 * Federated/social providers (Apple, Google, …) can be added later purely additively: a row in
 * `user_identities` links a provider subject to the same `users.id` — no reshaping of ownership.
 */

// --- Email + password credentials -------------------------------------------------------------

// bcrypt only consumes the first 72 bytes of its input. Pre-hashing with SHA-256 (base64, fixed
// ASCII, no null bytes) lets passwords be arbitrarily long without silent truncation. The scheme
// tag makes the stored hash self-describing so we can migrate to argon2id later without guessing.
const PW_SCHEME = 'bcrypt-sha256';
const BCRYPT_COST = 12;
const MIN_PASSWORD_LEN = 8;
const MAX_PASSWORD_LEN = 1024; // bound raw input so a giant body can't tie up CPU before hashing.

/** Canonical email form used for storage, the unique index, and login lookup (server-authoritative). */
export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
export function isValidEmail(email: string): boolean {
  return email.length <= 254 && EMAIL_RE.test(email);
}

export function isValidPassword(password: string): boolean {
  return password.length >= MIN_PASSWORD_LEN && password.length <= MAX_PASSWORD_LEN;
}

function prehash(password: string): string {
  return createHash('sha256').update(password, 'utf8').digest('base64');
}

export async function hashPassword(password: string): Promise<string> {
  const hash = await bcrypt.hash(prehash(password), BCRYPT_COST);
  return `${PW_SCHEME}$${hash}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const prefix = `${PW_SCHEME}$`;
  if (!stored.startsWith(prefix)) return false;
  return bcrypt.compare(prehash(password), stored.slice(prefix.length));
}

/** Thrown when a registration collides with an existing account (unique index on lower(email)). */
export class EmailTakenError extends Error {
  constructor() {
    super('email already registered');
    this.name = 'EmailTakenError';
  }
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

// --- Registration / login ---------------------------------------------------------------------

/**
 * Create a new account and its first session in a single transaction (so we never leave an
 * account with no usable session). The email must already be valid and the password length
 * checked by the caller. Throws `EmailTakenError` on a duplicate email — the unique index is the
 * real guard against the register race, not a prior SELECT.
 */
export async function registerUser(
  pool: pg.Pool,
  email: string,
  password: string,
  client: string | null,
  ttlDays = 30
): Promise<{ userId: string; sessionToken: string }> {
  const normalized = normalizeEmail(email);
  const passwordHash = await hashPassword(password);
  const token = newOpaqueToken();
  const expires = new Date(Date.now() + ttlDays * 86_400_000);

  const conn = await pool.connect();
  try {
    await conn.query('BEGIN');
    let userId: string;
    try {
      const u = await conn.query(
        `INSERT INTO public.users (email, password_hash) VALUES ($1, $2) RETURNING id`,
        [normalized, passwordHash]
      );
      userId = u.rows[0].id as string;
    } catch (err) {
      if ((err as { code?: string }).code === '23505') {
        await conn.query('ROLLBACK');
        throw new EmailTakenError();
      }
      throw err;
    }
    await conn.query(
      `INSERT INTO public.sessions (user_id, token_hash, client, expires_at)
       VALUES ($1, $2, $3, $4)`,
      [userId, hashToken(token), client, expires]
    );
    await conn.query('COMMIT');
    return { userId, sessionToken: token };
  } catch (err) {
    if (!(err instanceof EmailTakenError)) {
      try {
        await conn.query('ROLLBACK');
      } catch {
        /* already rolled back */
      }
    }
    throw err;
  } finally {
    conn.release();
  }
}

/**
 * Verify an email + password. Returns the internal user id on success, or null on either a missing
 * account or a wrong password — the caller surfaces a single generic error so the two are
 * indistinguishable to clients.
 */
export async function loginUser(
  pool: pg.Pool,
  email: string,
  password: string
): Promise<string | null> {
  const normalized = normalizeEmail(email);
  const r = await pool.query(
    `SELECT id, password_hash FROM public.users
     WHERE lower(email) = $1 AND password_hash IS NOT NULL`,
    [normalized]
  );
  if ((r.rowCount ?? 0) === 0) return null;
  const ok = await verifyPassword(password, r.rows[0].password_hash as string);
  return ok ? (r.rows[0].id as string) : null;
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
