import {
  exportJWK,
  importPKCS8,
  generateKeyPair,
  type JWK,
  type KeyLike,
} from 'jose';
import { createHash, createHmac, randomBytes, randomInt, timingSafeEqual } from 'crypto';
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

export async function userHasTotpEnabled(pool: pg.Pool, userId: string): Promise<boolean> {
  const r = await pool.query(
    `SELECT 1 FROM public.auth_totp_secrets
      WHERE user_id = $1 AND enabled_at IS NOT NULL AND disabled_at IS NULL
      LIMIT 1`,
    [userId]
  );
  return (r.rowCount ?? 0) > 0;
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
  pool: pg.Pool | pg.PoolClient,
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

// --- One-time email codes (passwordless login + password reset) -------------------------------

/**
 * Short-lived numeric codes emailed to a user for two flows that share one table (`auth_codes`):
 *  - `login`: passwordless sign-in — verifying a code signs in an existing user or creates a new
 *    (password-less) account.
 *  - `reset`: forgot-password — verifying a code authorises setting a new password.
 *
 * Codes are single-use, expiring, attempt-capped, and only the SHA-256 is stored (never the code).
 * Issuing a new code for an (email, purpose) consumes any earlier unconsumed ones so only the
 * newest works.
 */
export type CodePurpose = 'login' | 'reset';

export const CODE_TTL_LOGIN_MS = 10 * 60_000;
export const CODE_TTL_RESET_MS = 15 * 60_000;
export const CODE_MAX_ATTEMPTS = 5;

/** A 6-digit numeric one-time code (leading zeros preserved) — easy to read and type from an email. */
export function newNumericCode(digits = 6): string {
  return randomInt(0, 10 ** digits).toString().padStart(digits, '0');
}

export function hashCode(code: string): string {
  return createHash('sha256').update(code).digest('hex');
}

// --- TOTP + recovery codes ---------------------------------------------------------------------

const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const TOTP_STEP_SECONDS = 30;
const TOTP_DIGITS = 6;

export function newTotpSecret(): string {
  return base32Encode(randomBytes(20));
}

function base32Encode(bytes: Uint8Array): string {
  let bits = 0;
  let value = 0;
  let out = '';
  for (const byte of bytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += BASE32_ALPHABET[(value << (5 - bits)) & 31];
  return out;
}

function base32Decode(secret: string): Buffer {
  const clean = secret.toUpperCase().replace(/[^A-Z2-7]/g, '');
  let bits = 0;
  let value = 0;
  const out: number[] = [];
  for (const char of clean) {
    const idx = BASE32_ALPHABET.indexOf(char);
    if (idx < 0) continue;
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

export function totpUri(email: string, secret: string, issuer = 'Capture'): string {
  const label = `${issuer}:${normalizeEmail(email)}`;
  const params = new URLSearchParams({
    secret,
    issuer,
    algorithm: 'SHA1',
    digits: String(TOTP_DIGITS),
    period: String(TOTP_STEP_SECONDS),
  });
  return `otpauth://totp/${encodeURIComponent(label)}?${params.toString()}`;
}

function totpAt(secret: string, counter: number): string {
  const msg = Buffer.alloc(8);
  msg.writeBigUInt64BE(BigInt(counter));
  const digest = createHmac('sha1', base32Decode(secret)).update(msg).digest();
  const offset = digest[digest.length - 1] & 0xf;
  const binary =
    ((digest[offset] & 0x7f) << 24) |
    ((digest[offset + 1] & 0xff) << 16) |
    ((digest[offset + 2] & 0xff) << 8) |
    (digest[offset + 3] & 0xff);
  return (binary % 10 ** TOTP_DIGITS).toString().padStart(TOTP_DIGITS, '0');
}

function safeEqualString(a: string, b: string): boolean {
  const aa = Buffer.from(a);
  const bb = Buffer.from(b);
  return aa.length === bb.length && timingSafeEqual(aa, bb);
}

export function verifyTotpCode(secret: string, code: string, now = Date.now(), window = 1): boolean {
  const clean = code.replace(/\s+/g, '');
  if (!/^\d{6}$/.test(clean)) return false;
  const counter = Math.floor(now / 1000 / TOTP_STEP_SECONDS);
  for (let drift = -window; drift <= window; drift++) {
    if (safeEqualString(totpAt(secret, counter + drift), clean)) return true;
  }
  return false;
}

export function newRecoveryCodes(count = 10): string[] {
  return Array.from({ length: count }, () => {
    const raw = randomBytes(6).toString('hex').toUpperCase();
    return `${raw.slice(0, 4)}-${raw.slice(4, 8)}-${raw.slice(8, 12)}`;
  });
}

export function hashRecoveryCode(code: string): string {
  const normalized = code.toUpperCase().replace(/[^A-Z0-9]/g, '');
  return createHash('sha256').update(`capture-recovery:${normalized}`).digest('hex');
}

export function newMfaChallengeToken(): string {
  return randomBytes(32).toString('base64url');
}

/** Idempotently create the auth-codes table + lookup index (auto-migrates on deploy). */
export async function ensureAuthSchema(pool: pg.Pool): Promise<void> {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.auth_codes (
      id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      email      text NOT NULL,
      purpose    text NOT NULL,
      code_hash  text NOT NULL,
      user_id    uuid REFERENCES public.users(id) ON DELETE CASCADE,
      attempts   integer NOT NULL DEFAULT 0,
      expires_at timestamptz NOT NULL,
      consumed_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT now()
    )`);
  await pool.query(
    `CREATE INDEX IF NOT EXISTS auth_codes_lookup_idx
       ON public.auth_codes (lower(email), purpose, consumed_at)`
  );
  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.auth_totp_secrets (
     id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
     user_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
     secret      text NOT NULL,
     enabled_at  timestamptz,
     disabled_at timestamptz,
     created_at  timestamptz NOT NULL DEFAULT now()
    )`);
  await pool.query(
    `CREATE UNIQUE INDEX IF NOT EXISTS auth_totp_one_active_idx
      ON public.auth_totp_secrets (user_id)
      WHERE enabled_at IS NOT NULL AND disabled_at IS NULL`
  );
  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.auth_recovery_codes (
     id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
     user_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
     code_hash   text NOT NULL,
     used_at     timestamptz,
     revoked_at  timestamptz,
     created_at  timestamptz NOT NULL DEFAULT now(),
     UNIQUE (user_id, code_hash)
    )`);
  await pool.query(
    `CREATE INDEX IF NOT EXISTS auth_recovery_codes_user_active_idx
      ON public.auth_recovery_codes (user_id)
      WHERE used_at IS NULL AND revoked_at IS NULL`
  );
  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.auth_mfa_challenges (
     id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
     user_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
     token_hash  text NOT NULL UNIQUE,
     attempts    integer NOT NULL DEFAULT 0,
     expires_at  timestamptz NOT NULL,
     consumed_at timestamptz,
     created_at  timestamptz NOT NULL DEFAULT now()
    )`);
  await pool.query(
    `CREATE INDEX IF NOT EXISTS auth_mfa_challenges_lookup_idx
      ON public.auth_mfa_challenges (token_hash)
      WHERE consumed_at IS NULL`
  );
  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.auth_webauthn_credentials (
     id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
     user_id           uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
     credential_id     text NOT NULL UNIQUE,
     public_key        bytea NOT NULL,
     counter           bigint NOT NULL DEFAULT 0,
     transports        text[] NOT NULL DEFAULT '{}',
     device_type       text,
     backed_up         boolean NOT NULL DEFAULT false,
     name              text,
     created_at        timestamptz NOT NULL DEFAULT now(),
     last_used_at      timestamptz,
     revoked_at        timestamptz
    )`);
  await pool.query(
    `CREATE INDEX IF NOT EXISTS auth_webauthn_credentials_user_active_idx
      ON public.auth_webauthn_credentials (user_id)
      WHERE revoked_at IS NULL`
  );
  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.auth_webauthn_challenges (
     id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
     user_id        uuid REFERENCES public.users(id) ON DELETE CASCADE,
     purpose        text NOT NULL CHECK (purpose IN ('registration', 'authentication')),
     challenge_hash text NOT NULL UNIQUE,
     expires_at     timestamptz NOT NULL,
     consumed_at    timestamptz,
     created_at     timestamptz NOT NULL DEFAULT now()
    )`);
  await pool.query(
    `CREATE INDEX IF NOT EXISTS auth_webauthn_challenges_lookup_idx
      ON public.auth_webauthn_challenges (challenge_hash, purpose)
      WHERE consumed_at IS NULL`
  );
}

/**
 * Create + persist a one-time code and return the PLAINTEXT code (to email). Any earlier
 * unconsumed code for the same (email, purpose) is consumed first so only the newest is valid.
 */
export async function issueAuthCode(
  pool: pg.Pool,
  email: string,
  purpose: CodePurpose,
  userId: string | null,
  ttlMs: number
): Promise<string> {
  const normalized = normalizeEmail(email);
  const code = newNumericCode();
  const expires = new Date(Date.now() + ttlMs);
  await pool.query(
    `UPDATE public.auth_codes SET consumed_at = now()
       WHERE lower(email) = $1 AND purpose = $2 AND consumed_at IS NULL`,
    [normalized, purpose]
  );
  await pool.query(
    `INSERT INTO public.auth_codes (email, purpose, code_hash, user_id, expires_at)
     VALUES ($1, $2, $3, $4, $5)`,
    [normalized, purpose, hashCode(code), userId, expires]
  );
  return code;
}

export type CodeVerifyResult =
  | { ok: true; userId: string | null }
  | { ok: false; reason: 'invalid' | 'expired' | 'too_many_attempts' };

/**
 * Atomically verify the newest unconsumed code for (email, purpose). A wrong code increments
 * `attempts` (and is rejected once the cap is hit); a correct, unexpired code is marked consumed.
 * `FOR UPDATE` serialises concurrent verifies so attempts can't be raced past the cap.
 */
export async function verifyAuthCode(
  pool: pg.Pool,
  email: string,
  purpose: CodePurpose,
  code: string
): Promise<CodeVerifyResult> {
  const normalized = normalizeEmail(email);
  const conn = await pool.connect();
  try {
    await conn.query('BEGIN');
    const r = await conn.query(
      `SELECT id, code_hash, user_id, attempts, expires_at
         FROM public.auth_codes
        WHERE lower(email) = $1 AND purpose = $2 AND consumed_at IS NULL
        ORDER BY created_at DESC
        LIMIT 1
        FOR UPDATE`,
      [normalized, purpose]
    );
    if ((r.rowCount ?? 0) === 0) {
      await conn.query('COMMIT');
      return { ok: false, reason: 'invalid' };
    }
    const row = r.rows[0] as {
      id: string; code_hash: string; user_id: string | null; attempts: number; expires_at: string;
    };
    if (new Date(row.expires_at).getTime() < Date.now()) {
      await conn.query(`UPDATE public.auth_codes SET consumed_at = now() WHERE id = $1`, [row.id]);
      await conn.query('COMMIT');
      return { ok: false, reason: 'expired' };
    }
    if (row.attempts >= CODE_MAX_ATTEMPTS) {
      await conn.query(`UPDATE public.auth_codes SET consumed_at = now() WHERE id = $1`, [row.id]);
      await conn.query('COMMIT');
      return { ok: false, reason: 'too_many_attempts' };
    }
    if (hashCode(code) !== row.code_hash) {
      await conn.query(`UPDATE public.auth_codes SET attempts = attempts + 1 WHERE id = $1`, [row.id]);
      await conn.query('COMMIT');
      return { ok: false, reason: 'invalid' };
    }
    await conn.query(`UPDATE public.auth_codes SET consumed_at = now() WHERE id = $1`, [row.id]);
    await conn.query('COMMIT');
    return { ok: true, userId: row.user_id };
  } catch (err) {
    try { await conn.query('ROLLBACK'); } catch { /* already gone */ }
    throw err;
  } finally {
    conn.release();
  }
}

/** Find a user id by email, or create a new password-less account (email-code login of a new user). */
export async function findOrCreateUserByEmail(pool: pg.Pool, email: string): Promise<string> {
  const normalized = normalizeEmail(email);
  const sel = `SELECT id FROM public.users WHERE lower(email) = $1`;
  const found = await pool.query(sel, [normalized]);
  if ((found.rowCount ?? 0) > 0) return found.rows[0].id as string;
  try {
    const ins = await pool.query(`INSERT INTO public.users (email) VALUES ($1) RETURNING id`, [normalized]);
    return ins.rows[0].id as string;
  } catch (err) {
    if ((err as { code?: string }).code === '23505') {
      const again = await pool.query(sel, [normalized]); // lost the create race — read the winner
      if ((again.rowCount ?? 0) > 0) return again.rows[0].id as string;
    }
    throw err;
  }
}

/** Set a new password for a user and revoke all their existing sessions (forced re-login). */
export async function resetPassword(pool: pg.Pool, userId: string, newPassword: string): Promise<void> {
  const passwordHash = await hashPassword(newPassword);
  await pool.query(`UPDATE public.users SET password_hash = $1 WHERE id = $2`, [passwordHash, userId]);
  await pool.query(
    `UPDATE public.sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL`,
    [userId]
  );
}

/** Resolve an email to an existing user id (or null) — used by forgot-password without enumeration. */
export async function findUserIdByEmail(pool: pg.Pool, email: string): Promise<string | null> {
  const r = await pool.query(`SELECT id FROM public.users WHERE lower(email) = $1`, [normalizeEmail(email)]);
  return (r.rowCount ?? 0) > 0 ? (r.rows[0].id as string) : null;
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
