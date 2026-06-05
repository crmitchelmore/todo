import express, { type Request, type Response, type NextFunction } from 'express';
import cors from 'cors';
import pg from 'pg';
import { SignJWT } from 'jose';
import { createHash, randomUUID } from 'crypto';
import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
  type AuthenticationResponseJSON,
  type AuthenticatorTransportFuture,
  type RegistrationResponseJSON,
} from '@simplewebauthn/server';
import {
  registerUser,
  loginUser,
  createSession,
  lookupSession,
  revokeSession,
  loadSigningKey,
  normalizeEmail,
  isValidEmail,
  isValidPassword,
  EmailTakenError,
  ensureAuthSchema,
  issueAuthCode,
  verifyAuthCode,
  findOrCreateUserByEmail,
  findUserIdByEmail,
  resetPassword,
  CODE_TTL_LOGIN_MS,
  CODE_TTL_RESET_MS,
  hashRecoveryCode,
  hashToken,
  newMfaChallengeToken,
  newRecoveryCodes,
  newTotpSecret,
  totpUri,
  userHasTotpEnabled,
  verifyTotpCode,
} from './auth.js';
import {
  applyAgentProposalDecision,
  parseAgentProposalDecision,
  serializeResumePayload,
} from './agentDecision.js';
import { agentHandoffRequestId, parseAgentHandoffInput } from './agentHandoff.js';
import { validateAttachmentData } from './attachments.js';
import { sendEmailBestEffort, loginCodeEmail, resetCodeEmail } from './mailer.js';
import {
  githubAuthorizeUrl,
  githubOAuthConfig,
  oauthSessionFragment,
  primaryVerifiedGitHubEmail,
  randomOAuthNonce,
  signOAuthState,
  verifyOAuthState,
} from './oauth.js';

/**
 * Capture backend connector (multi-user, email + password auth).
 *
 *  - POST /api/auth/register Create an account (email + password) and return a session token.
 *  - POST /api/auth/login    Exchange email + password for an opaque session token.
 *  - POST /api/auth/logout   Revoke the caller's session.
 *  - GET  /api/auth/oauth/github/start  Start GitHub OAuth sign-in.
 *  - GET  /api/auth/keys     JWKS so the PowerSync service can verify the per-user sync tokens.
 *  - GET  /api/auth/token    Mint a short-lived per-user RS256 JWT + the PowerSync endpoint URL.
 *  - PUT  /api/data          Apply a batch of client CRUD ops to Postgres (owner-scoped write path).
 *  - POST /api/capture       Lightweight ingest for out-of-process surfaces (extensions/intents).
 *  - POST /api/tasks/:id/comments       Append a user-visible task comment.
 *  - POST /api/tasks/:id/agent-handoff  Queue a server-owned AI research/attempt request.
 */

const PORT = Number(process.env.BACKEND_PORT ?? 6060);
const DATABASE_URI = process.env.BACKEND_DATABASE_URI!;
const JWT_ISSUER = process.env.JWT_ISSUER ?? 'capture';
const JWT_AUDIENCE = process.env.JWT_AUDIENCE ?? 'powersync';
const POWERSYNC_URL = process.env.POWERSYNC_PUBLIC_URL ?? 'http://localhost:8080';
const PUBLIC_WEB_ORIGIN = process.env.PUBLIC_WEB_ORIGIN ?? 'http://localhost:3030';
const PUBLIC_BACKEND_ORIGIN = process.env.PUBLIC_BACKEND_ORIGIN;
const WEBAUTHN_RP_ID = process.env.WEBAUTHN_RP_ID ?? new URL(PUBLIC_WEB_ORIGIN).hostname;
const WEBAUTHN_RP_NAME = process.env.WEBAUTHN_RP_NAME ?? 'Capture';
const MFA_CHALLENGE_TTL_MS = 5 * 60_000;
const MFA_MAX_ATTEMPTS = 5;
const OAUTH_STATE_TTL_MS = 10 * 60_000;

const pool = new pg.Pool({ connectionString: DATABASE_URI });
const { privateKey, publicJwk, kid } = await loadSigningKey();

const app = express();
// Behind Railway's proxy: trust the first hop so req.ip reflects the real client for throttling.
app.set('trust proxy', 1);
app.use(cors());
app.use(express.json({ limit: '5mb' }));

// --- Brute-force throttle: cap failed credential attempts before doing expensive bcrypt work. ---
// In-memory (single Railway instance); resets on deploy. Good enough for a small user base — move
// to a Postgres/Redis-backed limiter before scaling out or opening signups widely.
const FAIL_WINDOW_MS = 15 * 60_000;
const FAIL_MAX = 10;
const failures = new Map<string, { count: number; resetAt: number }>();
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function attemptKey(ip: string, email: string): string {
  return `${ip}|${email}`;
}
function isThrottled(key: string): boolean {
  const e = failures.get(key);
  if (!e) return false;
  if (Date.now() > e.resetAt) {
    failures.delete(key);
    return false;
  }
  return e.count >= FAIL_MAX;
}
function recordFailure(key: string): void {
  const now = Date.now();
  const e = failures.get(key);
  if (!e || now > e.resetAt) failures.set(key, { count: 1, resetAt: now + FAIL_WINDOW_MS });
  else e.count += 1;
}
function clearFailures(key: string): void {
  failures.delete(key);
}

// --- Auth middleware: opaque session token -> req.ownerId -------------------------------------

interface AuthedRequest extends Request {
  ownerId?: string;
  sessionToken?: string;
}

function bearer(req: Request): string | undefined {
  const h = req.header('authorization');
  if (!h || !h.startsWith('Bearer ')) return undefined;
  const t = h.slice('Bearer '.length).trim();
  return t || undefined;
}

async function requireAuth(req: AuthedRequest, res: Response, next: NextFunction): Promise<void> {
  const token = bearer(req);
  if (!token) {
    res.status(401).json({ ok: false, error: 'unauthorized' });
    return;
  }
  try {
    const userId = await lookupSession(pool, token);
    if (!userId) {
      res.status(401).json({ ok: false, error: 'unauthorized' });
      return;
    }
    req.ownerId = userId;
    req.sessionToken = token;
    next();
  } catch (err) {
    console.error('session lookup failed:', err);
    res.status(500).json({ ok: false, error: 'auth error' });
  }
}

// --- Write-path safety: only these tables/columns may be mutated by clients. ------------------
const ALLOWED_COLUMNS: Record<string, Set<string>> = {
  tasks: new Set([
    'id', 'owner_id', 'parent_task_id', 'title', 'notes', 'status', 'category', 'tags', 'due_at', 'priority',
    'github_repo', 'github_url',
    'suggested_due_at', 'suggested_category', 'suggestion_confidence', 'suggestion_source',
    'source', 'created_at', 'updated_at', 'confirmed_at', 'completed_at'
  ]),
  tags: new Set([
    'id', 'owner_id', 'name', 'color', 'created_at', 'updated_at'
  ]),
  task_attachments: new Set([
    'id', 'owner_id', 'task_id', 'filename', 'mime_type', 'byte_size', 'preview_data_url', 'created_at'
  ])
};
const READ_ONLY_SYNC_TABLES = new Set(['task_events', 'agent_proposals']);

app.get('/api/health', (_req, res) => res.json({ ok: true }));

app.get('/api/auth/keys', (_req, res) => {
  res.json({ keys: [publicJwk] });
});

async function createMfaChallenge(userId: string): Promise<string> {
  const token = newMfaChallengeToken();
  await pool.query(
    `INSERT INTO public.auth_mfa_challenges (user_id, token_hash, expires_at)
     VALUES ($1, $2, $3)`,
    [userId, hashToken(token), new Date(Date.now() + MFA_CHALLENGE_TTL_MS)]
  );
  return token;
}

async function issueSessionOrMfa(
  res: Response,
  userId: string,
  client: string | null,
  options: { mfaSatisfied?: boolean; extra?: Record<string, unknown> } = {}
): Promise<void> {
  if (!options.mfaSatisfied && await userHasTotpEnabled(pool, userId)) {
    const challengeToken = await createMfaChallenge(userId);
    res.json({ ok: true, mfa_required: true, mfa_challenge: challengeToken });
    return;
  }
  const sessionToken = await createSession(pool, userId, client);
  res.json({ ok: true, session_token: sessionToken, user_id: userId, ...(options.extra ?? {}) });
}

class ExistingEmailNeedsLinkError extends Error {
  constructor() {
    super('email account must explicitly link this GitHub identity');
    this.name = 'ExistingEmailNeedsLinkError';
  }
}

class GitHubOAuthError extends Error {
  constructor(message: string, readonly code: string) {
    super(message);
    this.name = 'GitHubOAuthError';
  }
}

function publicBackendOrigin(req: Request): string {
  return PUBLIC_BACKEND_ORIGIN ?? `${req.protocol}://${req.get('host')}`;
}

function githubRedirectUri(req: Request): string {
  return `${publicBackendOrigin(req)}/api/auth/oauth/github/callback`;
}

function oauthErrorRedirect(code: string): string {
  const url = new URL(PUBLIC_WEB_ORIGIN);
  url.hash = new URLSearchParams({ capture_oauth: '1', error: code }).toString();
  return url.toString();
}

async function findOrCreateGitHubUser(subject: string, email: string): Promise<string> {
  const normalizedEmail = normalizeEmail(email);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const linked = await client.query(
      `SELECT user_id FROM public.user_identities
        WHERE provider = 'github' AND provider_subject = $1
        LIMIT 1`,
      [subject]
    );
    if ((linked.rowCount ?? 0) > 0) {
      await client.query('COMMIT');
      return linked.rows[0].user_id as string;
    }

    const existingEmail = await client.query(
      `SELECT id FROM public.users WHERE lower(email) = $1 LIMIT 1`,
      [normalizedEmail]
    );
    if ((existingEmail.rowCount ?? 0) > 0) {
      await client.query('ROLLBACK');
      throw new ExistingEmailNeedsLinkError();
    }

    const user = await client.query(
      `INSERT INTO public.users (email) VALUES ($1) RETURNING id`,
      [normalizedEmail]
    );
    const userId = user.rows[0].id as string;
    await client.query(
      `INSERT INTO public.user_identities (user_id, provider, provider_subject, email)
       VALUES ($1, 'github', $2, $3)`,
      [userId, subject, normalizedEmail]
    );
    await client.query('COMMIT');
    return userId;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    if ((err as { code?: string }).code === '23505') {
      const linked = await pool.query(
        `SELECT user_id FROM public.user_identities
          WHERE provider = 'github' AND provider_subject = $1
          LIMIT 1`,
        [subject]
      );
      if ((linked.rowCount ?? 0) > 0) return linked.rows[0].user_id as string;
      throw new ExistingEmailNeedsLinkError();
    }
    throw err;
  } finally {
    client.release();
  }
}

async function exchangeGitHubCode(code: string, redirectUri: string): Promise<string> {
  const config = githubOAuthConfig();
  if (!config) throw new GitHubOAuthError('GitHub OAuth is not configured', 'github_not_configured');
  const response = await fetch('https://github.com/login/oauth/access_token', {
    method: 'POST',
    headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_id: config.clientId,
      client_secret: config.clientSecret,
      code,
      redirect_uri: redirectUri,
    }),
  });
  const body = await response.json().catch(() => ({})) as Record<string, unknown>;
  const token = typeof body.access_token === 'string' ? body.access_token : null;
  if (!response.ok || !token) {
    throw new GitHubOAuthError('GitHub token exchange failed', 'github_exchange_failed');
  }
  return token;
}

async function fetchGitHubIdentity(accessToken: string): Promise<{ subject: string; email: string }> {
  const headers = {
    Accept: 'application/vnd.github+json',
    Authorization: `Bearer ${accessToken}`,
    'User-Agent': 'capture-auth',
    'X-GitHub-Api-Version': '2022-11-28',
  };
  const userResponse = await fetch('https://api.github.com/user', { headers });
  const user = await userResponse.json().catch(() => ({})) as Record<string, unknown>;
  const rawId = user.id;
  const subject = typeof rawId === 'number' || typeof rawId === 'string' ? String(rawId) : null;
  if (!userResponse.ok || !subject) {
    throw new GitHubOAuthError('GitHub profile lookup failed', 'github_profile_failed');
  }

  const emailResponse = await fetch('https://api.github.com/user/emails', { headers });
  const emails = await emailResponse.json().catch(() => []) as unknown;
  const email = emailResponse.ok ? primaryVerifiedGitHubEmail(emails) : null;
  if (!email || !isValidEmail(normalizeEmail(email))) {
    throw new GitHubOAuthError('GitHub account has no verified email', 'github_verified_email_required');
  }
  return { subject, email };
}

async function storeRecoveryCodes(client: pg.PoolClient, userId: string, codes: string[]): Promise<void> {
  await client.query(
    `UPDATE public.auth_recovery_codes
        SET revoked_at = now()
      WHERE user_id = $1 AND used_at IS NULL AND revoked_at IS NULL`,
    [userId]
  );
  for (const code of codes) {
    await client.query(
      `INSERT INTO public.auth_recovery_codes (user_id, code_hash) VALUES ($1, $2)
       ON CONFLICT (user_id, code_hash) DO NOTHING`,
      [userId, hashRecoveryCode(code)]
    );
  }
}

async function verifySecondFactor(
  client: pg.Pool | pg.PoolClient,
  userId: string,
  code: string
): Promise<'totp' | 'recovery' | null> {
  const cleaned = code.trim();
  const totp = await client.query(
    `SELECT secret FROM public.auth_totp_secrets
      WHERE user_id = $1 AND enabled_at IS NOT NULL AND disabled_at IS NULL
      LIMIT 1`,
    [userId]
  );
  if ((totp.rowCount ?? 0) > 0 && verifyTotpCode(totp.rows[0].secret as string, cleaned)) {
    return 'totp';
  }
  const recovery = await client.query(
    `UPDATE public.auth_recovery_codes
        SET used_at = now()
      WHERE user_id = $1 AND code_hash = $2 AND used_at IS NULL AND revoked_at IS NULL
      RETURNING id`,
    [userId, hashRecoveryCode(cleaned)]
  );
  return (recovery.rowCount ?? 0) > 0 ? 'recovery' : null;
}

async function consumeWebAuthnChallenge(
  challenge: string,
  purpose: 'registration' | 'authentication',
  userId: string | null
): Promise<boolean> {
  const r = await pool.query(
    `UPDATE public.auth_webauthn_challenges
        SET consumed_at = now()
      WHERE challenge_hash = $1
        AND purpose = $2
        AND ($3::uuid IS NULL OR user_id = $3 OR user_id IS NULL)
        AND consumed_at IS NULL
        AND expires_at > now()
      RETURNING id`,
    [hashToken(challenge), purpose, userId]
  );
  return (r.rowCount ?? 0) > 0;
}

/**
 * Register a new account (email + password) and return an opaque session token. Public endpoint;
 * the unique index on lower(email) enforces one account per email.
 */
app.post('/api/auth/register', async (req: Request, res: Response) => {
  const rawEmail = typeof req.body?.email === 'string' ? req.body.email : '';
  const password = typeof req.body?.password === 'string' ? req.body.password : '';
  const client: string | null =
    typeof req.body?.client === 'string' ? req.body.client.slice(0, 32) : null;
  const email = normalizeEmail(rawEmail);

  if (!isValidEmail(email)) {
    return res.status(400).json({ ok: false, error: 'a valid email is required' });
  }
  if (!isValidPassword(password)) {
    return res.status(400).json({ ok: false, error: 'password must be at least 8 characters' });
  }
  try {
    const { userId, sessionToken } = await registerUser(pool, email, password, client);
    res.json({ ok: true, session_token: sessionToken, user_id: userId });
  } catch (err) {
    if (err instanceof EmailTakenError) {
      return res.status(409).json({ ok: false, error: 'that email is already registered' });
    }
    console.error('register failed:', err);
    res.status(500).json({ ok: false, error: 'registration failed' });
  }
});

/**
 * Exchange email + password for an opaque session token. A wrong password and an unknown email
 * return the SAME generic 401 (no account enumeration on this path). Failed attempts are throttled
 * per ip+email BEFORE the bcrypt compare so the hash can't be used as a CPU amplifier.
 */
app.post('/api/auth/login', async (req: Request, res: Response) => {
  const rawEmail = typeof req.body?.email === 'string' ? req.body.email : '';
  const password = typeof req.body?.password === 'string' ? req.body.password : '';
  const client: string | null =
    typeof req.body?.client === 'string' ? req.body.client.slice(0, 32) : null;
  const email = normalizeEmail(rawEmail);

  if (!email || !password) {
    return res.status(400).json({ ok: false, error: 'email and password are required' });
  }
  const key = attemptKey(req.ip ?? 'unknown', email);
  if (isThrottled(key)) {
    return res.status(429).json({ ok: false, error: 'too many attempts, try again later' });
  }
  try {
    const userId = await loginUser(pool, email, password);
    if (!userId) {
      recordFailure(key);
      return res.status(401).json({ ok: false, error: 'invalid email or password' });
    }
    clearFailures(key);
    await issueSessionOrMfa(res, userId, client);
  } catch (err) {
    console.error('login failed:', err);
    res.status(500).json({ ok: false, error: 'login failed' });
  }
});

app.post('/api/auth/login/mfa', async (req: Request, res: Response) => {
  const challengeToken = typeof req.body?.mfa_challenge === 'string' ? req.body.mfa_challenge : '';
  const code = typeof req.body?.code === 'string' ? req.body.code : '';
  const clientName: string | null =
    typeof req.body?.client === 'string' ? req.body.client.slice(0, 32) : null;
  if (!challengeToken || !code.trim()) {
    return res.status(400).json({ ok: false, error: 'challenge and code are required' });
  }

  const conn = await pool.connect();
  try {
    await conn.query('BEGIN');
    const challenge = await conn.query(
      `SELECT id, user_id, attempts, expires_at
         FROM public.auth_mfa_challenges
        WHERE token_hash = $1 AND consumed_at IS NULL
        ORDER BY created_at DESC
        LIMIT 1
        FOR UPDATE`,
      [hashToken(challengeToken)]
    );
    if ((challenge.rowCount ?? 0) === 0) {
      await conn.query('COMMIT');
      return res.status(401).json({ ok: false, error: 'invalid or expired challenge' });
    }
    const row = challenge.rows[0] as { id: string; user_id: string; attempts: number; expires_at: string };
    if (new Date(row.expires_at).getTime() < Date.now() || row.attempts >= MFA_MAX_ATTEMPTS) {
      await conn.query(`UPDATE public.auth_mfa_challenges SET consumed_at = now() WHERE id = $1`, [row.id]);
      await conn.query('COMMIT');
      return res.status(401).json({ ok: false, error: 'invalid or expired challenge' });
    }
    const method = await verifySecondFactor(conn, row.user_id, code);
    if (!method) {
      await conn.query(`UPDATE public.auth_mfa_challenges SET attempts = attempts + 1 WHERE id = $1`, [row.id]);
      await conn.query('COMMIT');
      return res.status(401).json({ ok: false, error: 'invalid authentication code' });
    }
    await conn.query(`UPDATE public.auth_mfa_challenges SET consumed_at = now() WHERE id = $1`, [row.id]);
    const sessionToken = await createSession(conn, row.user_id, clientName);
    await conn.query('COMMIT');
    res.json({ ok: true, session_token: sessionToken, user_id: row.user_id, mfa_method: method });
  } catch (err) {
    await conn.query('ROLLBACK').catch(() => {});
    console.error('mfa login failed:', err);
    res.status(500).json({ ok: false, error: 'sign-in failed' });
  } finally {
    conn.release();
  }
});

app.post('/api/auth/logout', requireAuth, async (req: AuthedRequest, res: Response) => {
  try {
    if (req.sessionToken) await revokeSession(pool, req.sessionToken);
    res.json({ ok: true });
  } catch (err) {
    console.error('logout failed:', err);
    res.status(500).json({ ok: false, error: 'logout failed' });
  }
});

app.get('/api/auth/oauth/providers', (_req: Request, res: Response) => {
  res.json({
    ok: true,
    github: { configured: Boolean(githubOAuthConfig()) },
  });
});

app.get('/api/auth/oauth/github/start', (req: Request, res: Response) => {
  const config = githubOAuthConfig();
  if (!config) {
    return res.status(503).json({ ok: false, error: 'GitHub sign-in is not configured' });
  }
  const state = signOAuthState(
    { nonce: randomOAuthNonce(), exp: Date.now() + OAUTH_STATE_TTL_MS },
    config.stateSecret
  );
  return res.redirect(302, githubAuthorizeUrl({
    clientId: config.clientId,
    redirectUri: githubRedirectUri(req),
    state,
  }));
});

app.get('/api/auth/oauth/github/callback', async (req: Request, res: Response) => {
  const config = githubOAuthConfig();
  const code = typeof req.query.code === 'string' ? req.query.code : '';
  const state = typeof req.query.state === 'string' ? req.query.state : '';
  if (!config) return res.redirect(303, oauthErrorRedirect('github_not_configured'));
  if (!code || !verifyOAuthState(state, config.stateSecret)) {
    return res.redirect(303, oauthErrorRedirect('github_invalid_state'));
  }

  try {
    const token = await exchangeGitHubCode(code, githubRedirectUri(req));
    const identity = await fetchGitHubIdentity(token);
    const userId = await findOrCreateGitHubUser(identity.subject, identity.email);
    const sessionToken = await createSession(pool, userId, 'web-github');
    return res.redirect(303, oauthSessionFragment({ origin: PUBLIC_WEB_ORIGIN, sessionToken, userId }));
  } catch (err) {
    if (err instanceof ExistingEmailNeedsLinkError) {
      return res.redirect(303, oauthErrorRedirect('github_email_needs_linking'));
    }
    if (err instanceof GitHubOAuthError) {
      console.warn('github oauth failed:', err.code);
      return res.redirect(303, oauthErrorRedirect(err.code));
    }
    console.error('github oauth failed:', err);
    return res.redirect(303, oauthErrorRedirect('github_failed'));
  }
});

/**
 * Passwordless login — step 1: email a one-time code. Always 200 (no account enumeration). A new
 * email simply gets a code and becomes an account on verify. Throttled per ip+email to stop an
 * attacker from spamming someone's inbox.
 */
app.post('/api/auth/email-code', async (req: Request, res: Response) => {
  const email = normalizeEmail(typeof req.body?.email === 'string' ? req.body.email : '');
  if (!isValidEmail(email)) {
    return res.status(400).json({ ok: false, error: 'a valid email is required' });
  }
  const key = attemptKey(req.ip ?? 'unknown', `code:${email}`);
  if (isThrottled(key)) {
    return res.status(429).json({ ok: false, error: 'too many requests, try again later' });
  }
  recordFailure(key); // count issuance against the same window (cap emails per ip+email)
  try {
    const code = await issueAuthCode(pool, email, 'login', null, CODE_TTL_LOGIN_MS);
    await sendEmailBestEffort(loginCodeEmail(email, code, CODE_TTL_LOGIN_MS / 60_000));
  } catch (err) {
    console.error('email-code issue failed:', err);
  }
  res.json({ ok: true }); // uniform response regardless of outcome
});

/**
 * Passwordless login — step 2: verify the code and issue a session. Signs in an existing user or
 * creates a new password-less account for a first-time email.
 */
app.post('/api/auth/email-code/verify', async (req: Request, res: Response) => {
  const email = normalizeEmail(typeof req.body?.email === 'string' ? req.body.email : '');
  const code = typeof req.body?.code === 'string' ? req.body.code.trim() : '';
  const client: string | null =
    typeof req.body?.client === 'string' ? req.body.client.slice(0, 32) : null;
  if (!isValidEmail(email) || !code) {
    return res.status(400).json({ ok: false, error: 'email and code are required' });
  }
  try {
    const result = await verifyAuthCode(pool, email, 'login', code);
    if (!result.ok) {
      const status = result.reason === 'too_many_attempts' ? 429 : 401;
      return res.status(status).json({ ok: false, error: 'that code is invalid or has expired' });
    }
    const userId = result.userId ?? (await findOrCreateUserByEmail(pool, email));
    await issueSessionOrMfa(res, userId, client);
  } catch (err) {
    console.error('email-code verify failed:', err);
    res.status(500).json({ ok: false, error: 'sign-in failed' });
  }
});

/**
 * Forgot password — step 1: email a reset code. Always 200 (no enumeration): a code is only
 * actually issued/sent when the email maps to a real account, but the response never reveals that.
 */
app.post('/api/auth/forgot', async (req: Request, res: Response) => {
  const email = normalizeEmail(typeof req.body?.email === 'string' ? req.body.email : '');
  if (!isValidEmail(email)) {
    return res.status(400).json({ ok: false, error: 'a valid email is required' });
  }
  const key = attemptKey(req.ip ?? 'unknown', `reset:${email}`);
  if (isThrottled(key)) {
    return res.status(429).json({ ok: false, error: 'too many requests, try again later' });
  }
  recordFailure(key);
  try {
    const userId = await findUserIdByEmail(pool, email);
    if (userId) {
      const code = await issueAuthCode(pool, email, 'reset', userId, CODE_TTL_RESET_MS);
      await sendEmailBestEffort(resetCodeEmail(email, code, CODE_TTL_RESET_MS / 60_000));
    }
  } catch (err) {
    console.error('forgot-password issue failed:', err);
  }
  res.json({ ok: true });
});

/**
 * Forgot password — step 2: verify the reset code, set a new password, revoke existing sessions,
 * and hand back a fresh session so the user is signed in immediately.
 */
app.post('/api/auth/reset', async (req: Request, res: Response) => {
  const email = normalizeEmail(typeof req.body?.email === 'string' ? req.body.email : '');
  const code = typeof req.body?.code === 'string' ? req.body.code.trim() : '';
  const password = typeof req.body?.password === 'string' ? req.body.password : '';
  const client: string | null =
    typeof req.body?.client === 'string' ? req.body.client.slice(0, 32) : null;
  if (!isValidEmail(email) || !code) {
    return res.status(400).json({ ok: false, error: 'email and code are required' });
  }
  if (!isValidPassword(password)) {
    return res.status(400).json({ ok: false, error: 'password must be at least 8 characters' });
  }
  try {
    const result = await verifyAuthCode(pool, email, 'reset', code);
    if (!result.ok || !result.userId) {
      const status = result.ok === false && result.reason === 'too_many_attempts' ? 429 : 401;
      return res.status(status).json({ ok: false, error: 'that code is invalid or has expired' });
    }
    await resetPassword(pool, result.userId, password);
    await issueSessionOrMfa(res, result.userId, client);
  } catch (err) {
    console.error('password reset failed:', err);
    res.status(500).json({ ok: false, error: 'reset failed' });
  }
});

app.post('/api/auth/totp/setup', requireAuth, async (req: AuthedRequest, res: Response) => {
  try {
    const user = await pool.query(`SELECT email FROM public.users WHERE id = $1`, [req.ownerId]);
    const email = (user.rows[0]?.email as string | null) ?? req.ownerId!;
    const secret = newTotpSecret();
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `UPDATE public.auth_totp_secrets
            SET disabled_at = now()
          WHERE user_id = $1 AND enabled_at IS NULL AND disabled_at IS NULL`,
        [req.ownerId]
      );
      await client.query(
        `INSERT INTO public.auth_totp_secrets (user_id, secret) VALUES ($1, $2)`,
        [req.ownerId, secret]
      );
      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      throw err;
    } finally {
      client.release();
    }
    res.json({ ok: true, secret, otpauth_uri: totpUri(email, secret) });
  } catch (err) {
    console.error('totp setup failed:', err);
    res.status(500).json({ ok: false, error: 'setup failed' });
  }
});

app.post('/api/auth/totp/verify', requireAuth, async (req: AuthedRequest, res: Response) => {
  const code = typeof req.body?.code === 'string' ? req.body.code : '';
  if (!code.trim()) return res.status(400).json({ ok: false, error: 'code is required' });
  const conn = await pool.connect();
  try {
    await conn.query('BEGIN');
    const pending = await conn.query(
      `SELECT id, secret FROM public.auth_totp_secrets
        WHERE user_id = $1 AND enabled_at IS NULL AND disabled_at IS NULL
        ORDER BY created_at DESC
        LIMIT 1
        FOR UPDATE`,
      [req.ownerId]
    );
    if ((pending.rowCount ?? 0) === 0) {
      await conn.query('COMMIT');
      return res.status(404).json({ ok: false, error: 'no pending setup' });
    }
    const row = pending.rows[0] as { id: string; secret: string };
    if (!verifyTotpCode(row.secret, code)) {
      await conn.query('COMMIT');
      return res.status(401).json({ ok: false, error: 'invalid authentication code' });
    }
    await conn.query(`UPDATE public.auth_totp_secrets SET enabled_at = now() WHERE id = $1`, [row.id]);
    const recoveryCodes = newRecoveryCodes();
    await storeRecoveryCodes(conn, req.ownerId!, recoveryCodes);
    await conn.query('COMMIT');
    res.json({ ok: true, recovery_codes: recoveryCodes });
  } catch (err) {
    await conn.query('ROLLBACK').catch(() => {});
    console.error('totp verify failed:', err);
    res.status(500).json({ ok: false, error: 'verification failed' });
  } finally {
    conn.release();
  }
});

app.post('/api/auth/totp/disable', requireAuth, async (req: AuthedRequest, res: Response) => {
  const code = typeof req.body?.code === 'string' ? req.body.code : '';
  if (!code.trim()) return res.status(400).json({ ok: false, error: 'code is required' });
  const conn = await pool.connect();
  try {
    await conn.query('BEGIN');
    const method = await verifySecondFactor(conn, req.ownerId!, code);
    if (!method) {
      await conn.query('COMMIT');
      return res.status(401).json({ ok: false, error: 'invalid authentication code' });
    }
    await conn.query(
      `UPDATE public.auth_totp_secrets
          SET disabled_at = now()
        WHERE user_id = $1 AND disabled_at IS NULL`,
      [req.ownerId]
    );
    await conn.query(
      `UPDATE public.auth_recovery_codes
          SET revoked_at = now()
        WHERE user_id = $1 AND used_at IS NULL AND revoked_at IS NULL`,
      [req.ownerId]
    );
    await conn.query('COMMIT');
    res.json({ ok: true, mfa_method: method });
  } catch (err) {
    await conn.query('ROLLBACK').catch(() => {});
    console.error('totp disable failed:', err);
    res.status(500).json({ ok: false, error: 'disable failed' });
  } finally {
    conn.release();
  }
});

app.post('/api/auth/recovery-codes/rotate', requireAuth, async (req: AuthedRequest, res: Response) => {
  const code = typeof req.body?.code === 'string' ? req.body.code : '';
  if (!code.trim()) return res.status(400).json({ ok: false, error: 'code is required' });
  const conn = await pool.connect();
  try {
    await conn.query('BEGIN');
    const method = await verifySecondFactor(conn, req.ownerId!, code);
    if (!method) {
      await conn.query('COMMIT');
      return res.status(401).json({ ok: false, error: 'invalid authentication code' });
    }
    const recoveryCodes = newRecoveryCodes();
    await storeRecoveryCodes(conn, req.ownerId!, recoveryCodes);
    await conn.query('COMMIT');
    res.json({ ok: true, recovery_codes: recoveryCodes, mfa_method: method });
  } catch (err) {
    await conn.query('ROLLBACK').catch(() => {});
    console.error('recovery-code rotation failed:', err);
    res.status(500).json({ ok: false, error: 'rotation failed' });
  } finally {
    conn.release();
  }
});

app.post('/api/auth/passkeys/register/options', requireAuth, async (req: AuthedRequest, res: Response) => {
  try {
    const user = await pool.query(`SELECT email FROM public.users WHERE id = $1`, [req.ownerId]);
    const email = (user.rows[0]?.email as string | null) ?? req.ownerId!;
    const credentials = await pool.query(
      `SELECT credential_id, transports FROM public.auth_webauthn_credentials
        WHERE user_id = $1 AND revoked_at IS NULL`,
      [req.ownerId]
    );
    const options = await generateRegistrationOptions({
      rpName: WEBAUTHN_RP_NAME,
      rpID: WEBAUTHN_RP_ID,
      userName: email,
      userDisplayName: email,
      userID: Buffer.from(req.ownerId!.replace(/-/g, ''), 'hex'),
      attestationType: 'none',
      authenticatorSelection: { residentKey: 'preferred', userVerification: 'required' },
      excludeCredentials: credentials.rows.map((row) => ({
        id: row.credential_id as string,
        transports: row.transports as AuthenticatorTransportFuture[],
      })),
    });
    await pool.query(
      `INSERT INTO public.auth_webauthn_challenges (user_id, purpose, challenge_hash, expires_at)
       VALUES ($1, 'registration', $2, $3)`,
      [req.ownerId, hashToken(options.challenge), new Date(Date.now() + 5 * 60_000)]
    );
    res.json({ ok: true, options });
  } catch (err) {
    console.error('passkey registration options failed:', err);
    res.status(500).json({ ok: false, error: 'passkey setup failed' });
  }
});

app.post('/api/auth/passkeys/register/verify', requireAuth, async (req: AuthedRequest, res: Response) => {
  const response = req.body?.response as RegistrationResponseJSON | undefined;
  if (!response) return res.status(400).json({ ok: false, error: 'response is required' });
  try {
    const verification = await verifyRegistrationResponse({
      response,
      expectedOrigin: PUBLIC_WEB_ORIGIN,
      expectedRPID: WEBAUTHN_RP_ID,
      requireUserVerification: true,
      expectedChallenge: (challenge) => consumeWebAuthnChallenge(challenge, 'registration', req.ownerId!),
    });
    if (!verification.verified) {
      return res.status(401).json({ ok: false, error: 'passkey verification failed' });
    }
    const { credential, credentialDeviceType, credentialBackedUp } = verification.registrationInfo;
    await pool.query(
      `INSERT INTO public.auth_webauthn_credentials
         (user_id, credential_id, public_key, counter, transports, device_type, backed_up, name)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       ON CONFLICT (credential_id) DO NOTHING`,
      [
        req.ownerId,
        credential.id,
        Buffer.from(credential.publicKey),
        credential.counter,
        credential.transports ?? [],
        credentialDeviceType,
        credentialBackedUp,
        typeof req.body?.name === 'string' ? req.body.name.slice(0, 80) : null,
      ]
    );
    res.json({ ok: true });
  } catch (err) {
    console.error('passkey registration verify failed:', err);
    res.status(500).json({ ok: false, error: 'passkey setup failed' });
  }
});

app.post('/api/auth/passkeys/login/options', async (req: Request, res: Response) => {
  const email = normalizeEmail(typeof req.body?.email === 'string' ? req.body.email : '');
  try {
    let userId: string | null = null;
    let allowCredentials: { id: string; transports?: AuthenticatorTransportFuture[] }[] | undefined;
    if (email) {
      const user = await pool.query(`SELECT id FROM public.users WHERE lower(email) = $1`, [email]);
      if ((user.rowCount ?? 0) > 0) {
        userId = user.rows[0].id as string;
        const creds = await pool.query(
          `SELECT credential_id, transports FROM public.auth_webauthn_credentials
            WHERE user_id = $1 AND revoked_at IS NULL`,
          [userId]
        );
        allowCredentials = creds.rows.map((row) => ({
          id: row.credential_id as string,
          transports: row.transports as AuthenticatorTransportFuture[],
        }));
      }
    }
    const options = await generateAuthenticationOptions({
      rpID: WEBAUTHN_RP_ID,
      allowCredentials,
      userVerification: 'required',
    });
    await pool.query(
      `INSERT INTO public.auth_webauthn_challenges (user_id, purpose, challenge_hash, expires_at)
       VALUES ($1, 'authentication', $2, $3)`,
      [userId, hashToken(options.challenge), new Date(Date.now() + 5 * 60_000)]
    );
    res.json({ ok: true, options });
  } catch (err) {
    console.error('passkey login options failed:', err);
    res.status(500).json({ ok: false, error: 'passkey sign-in failed' });
  }
});

app.post('/api/auth/passkeys/login/verify', async (req: Request, res: Response) => {
  const response = req.body?.response as AuthenticationResponseJSON | undefined;
  const clientName: string | null =
    typeof req.body?.client === 'string' ? req.body.client.slice(0, 32) : null;
  if (!response) return res.status(400).json({ ok: false, error: 'response is required' });
  try {
    const stored = await pool.query(
      `SELECT id, user_id, credential_id, public_key, counter, transports
         FROM public.auth_webauthn_credentials
        WHERE credential_id = $1 AND revoked_at IS NULL
        LIMIT 1`,
      [response.id]
    );
    if ((stored.rowCount ?? 0) === 0) {
      return res.status(401).json({ ok: false, error: 'passkey not recognised' });
    }
    const row = stored.rows[0] as {
      id: string; user_id: string; credential_id: string; public_key: Buffer; counter: string; transports: string[];
    };
    const verification = await verifyAuthenticationResponse({
      response,
      expectedOrigin: PUBLIC_WEB_ORIGIN,
      expectedRPID: WEBAUTHN_RP_ID,
      requireUserVerification: true,
      expectedChallenge: (challenge) => consumeWebAuthnChallenge(challenge, 'authentication', row.user_id),
      credential: {
        id: row.credential_id,
        publicKey: new Uint8Array(row.public_key),
        counter: Number(row.counter),
        transports: row.transports as AuthenticatorTransportFuture[],
      },
    });
    if (!verification.verified) {
      return res.status(401).json({ ok: false, error: 'passkey verification failed' });
    }
    await pool.query(
      `UPDATE public.auth_webauthn_credentials
          SET counter = $1, last_used_at = now()
        WHERE id = $2`,
      [verification.authenticationInfo.newCounter, row.id]
    );
    await issueSessionOrMfa(res, row.user_id, clientName);
  } catch (err) {
    console.error('passkey login verify failed:', err);
    res.status(500).json({ ok: false, error: 'passkey sign-in failed' });
  }
});

app.get('/api/auth/token', requireAuth, async (req: AuthedRequest, res: Response) => {
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: 'RS256', kid })
    .setSubject(req.ownerId!)
    .setIssuer(JWT_ISSUER)
    .setAudience(JWT_AUDIENCE)
    .setIssuedAt()
    .setExpirationTime('5m')
    .sign(privateKey);
  res.json({ token, powersync_url: POWERSYNC_URL });
});

interface CrudOp {
  op: 'PUT' | 'PATCH' | 'DELETE';
  type: string; // table name
  id: string;
  data?: Record<string, unknown>;
}

type TaskEventType =
  | 'captured'
  | 'confirmed'
  | 'updated'
  | 'completed'
  | 'reopened'
  | 'deleted'
  | 'enriched'
  | 'agent_requested'
  | 'agent_completed'
  | 'agent_failed'
  | 'commented';

interface TaskEventInput {
  ownerId: string;
  taskId: string;
  actor: 'user' | 'system' | 'worker' | 'agent' | 'api';
  eventType: TaskEventType;
  title: string;
  body?: string | null;
  metadata?: Record<string, unknown>;
  idempotencyKey: string;
}

function sanitize(table: string, data: Record<string, unknown>): Record<string, unknown> {
  const allowed = ALLOWED_COLUMNS[table];
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(data)) {
    if (allowed.has(k)) out[k] = v;
  }
  return out;
}

function deterministicUuid(input: string): string {
  const chars = createHash('sha256').update(input).digest('hex').slice(0, 32).split('');
  chars[12] = '5'; // version 5-ish deterministic UUID (hash-derived, not namespace RFC4122)
  chars[16] = ((Number.parseInt(chars[16], 16) & 0x3) | 0x8).toString(16);
  const h = chars.join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

function stableJSON(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableJSON).join(',')}]`;
  return `{${Object.keys(value as Record<string, unknown>)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${stableJSON((value as Record<string, unknown>)[key])}`)
    .join(',')}}`;
}

function boundText(value: string | null | undefined, max: number): string | null {
  if (!value) return null;
  return value.length <= max ? value : `${value.slice(0, max - 1)}…`;
}

function eventMetadata(metadata: Record<string, unknown> | undefined): string | null {
  if (!metadata) return null;
  const encoded = stableJSON(metadata);
  if (Buffer.byteLength(encoded, 'utf8') <= 4096) return encoded;
  return stableJSON({ truncated: true });
}

interface TaskEventState {
  id: string;
  title: string | null;
  notes: string | null;
  status: string | null;
  category: string | null;
  tags: string | null;
  due_at: unknown;
  priority: unknown;
  github_repo: string | null;
  github_url: string | null;
}

async function readTaskEventState(
  client: pg.PoolClient,
  ownerId: string,
  taskId: string
): Promise<TaskEventState | null> {
  const result = await client.query<TaskEventState>(
    `SELECT id, title, notes, status, category, tags, due_at, priority, github_repo, github_url
       FROM public.tasks
      WHERE id = $1 AND owner_id = $2
      LIMIT 1`,
    [taskId, ownerId]
  );
  return result.rows[0] ?? null;
}

async function recordTaskEvent(client: pg.PoolClient, input: TaskEventInput): Promise<void> {
  const id = deterministicUuid(`${input.ownerId}:${input.taskId}:${input.eventType}:${input.idempotencyKey}`);
  await client.query(
    `INSERT INTO public.task_events
       (id, owner_id, task_id, actor, event_type, title, body, metadata)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     ON CONFLICT (id) DO NOTHING`,
    [
      id,
      input.ownerId,
      input.taskId,
      input.actor,
      input.eventType,
      boundText(input.title, 160),
      boundText(input.body, 2000),
      eventMetadata(input.metadata),
    ]
  );
}

interface SemanticTaskChange {
  field: string;
  title: string;
  body: string;
  before: unknown;
  after: unknown;
}

const HUMAN_TASK_FIELDS = [
  'title',
  'notes',
  'due_at',
  'category',
  'tags',
  'priority',
  'github_repo',
  'github_url',
] as const;

function normalizeTaskValue(value: unknown): unknown {
  if (value === undefined) return null;
  if (value instanceof Date) return value.toISOString();
  return value;
}

function taskValue(row: TaskEventState | null, field: string): unknown {
  if (!row) return null;
  return normalizeTaskValue((row as unknown as Record<string, unknown>)[field]);
}

function describeDue(value: unknown): string {
  if (typeof value !== 'string' || value.length === 0) return 'none';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString('en-GB', {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function describePriority(value: unknown): string {
  return value === null || value === undefined || value === '' ? 'none' : `P${value}`;
}

function metadataScalar(value: unknown): unknown {
  const normalized = normalizeTaskValue(value);
  if (typeof normalized !== 'string') return normalized ?? null;
  if (normalized.length <= 300) return normalized;
  return { truncated: true, length: normalized.length, preview: normalized.slice(0, 180) };
}

function boundedMetadataValue(value: unknown): unknown {
  return metadataScalar(value);
}

function semanticTaskChanges(before: TaskEventState | null, data: Record<string, unknown>): SemanticTaskChange[] {
  const out: SemanticTaskChange[] = [];
  for (const field of HUMAN_TASK_FIELDS) {
    if (!(field in data)) continue;
    const previous = taskValue(before, field);
    const next = normalizeTaskValue(data[field]);
    if (stableJSON(previous) === stableJSON(next)) continue;

    if (field === 'title') {
      out.push({
        field,
        title: 'Renamed task',
        body: typeof next === 'string' ? `Now “${next.slice(0, 160)}”.` : 'Task title changed.',
        before: previous,
        after: next,
      });
      continue;
    }
    if (field === 'notes') {
      out.push({
        field,
        title: 'Description updated',
        body: next ? 'Expanded description changed.' : 'Expanded description cleared.',
        before: previous,
        after: next,
      });
      continue;
    }
    if (field === 'due_at') {
      out.push({
        field,
        title: previous ? (next ? 'Due date moved' : 'Due date cleared') : 'Due date set',
        body: next ? `Due ${describeDue(next)}.` : 'No due date.',
        before: previous,
        after: next,
      });
      continue;
    }
    if (field === 'category') {
      out.push({
        field,
        title: next ? `Moved to ${next}` : 'Category cleared',
        body: previous && next ? `Category changed from ${previous} to ${next}.` : `Category ${next ?? 'cleared'}.`,
        before: previous,
        after: next,
      });
      continue;
    }
    if (field === 'tags') {
      out.push({
        field,
        title: 'Tags updated',
        body: typeof next === 'string' && next !== '[]' ? `Tags ${next}.` : 'Tags cleared.',
        before: previous,
        after: next,
      });
      continue;
    }
    if (field === 'priority') {
      out.push({
        field,
        title: next === null || next === undefined ? 'Priority cleared' : `Priority set to ${describePriority(next)}`,
        body: `Priority ${describePriority(previous)} → ${describePriority(next)}.`,
        before: previous,
        after: next,
      });
      continue;
    }
    if (field === 'github_repo' || field === 'github_url') {
      out.push({
        field,
        title: next ? 'Linked GitHub project' : 'GitHub project cleared',
        body: typeof next === 'string' ? next : 'No GitHub project associated.',
        before: previous,
        after: next,
      });
    }
  }
  return out;
}

function taskEventForOp(
  op: CrudOp,
  applied: boolean,
  before: TaskEventState | null
): Omit<TaskEventInput, 'ownerId' | 'actor' | 'taskId' | 'idempotencyKey'> | null {
  if (!applied || op.type !== 'tasks' || op.op === 'DELETE') return null;
  const data = op.data ?? {};
  const status = typeof data.status === 'string' ? data.status : null;
  if (!before && status === 'proposed') {
    const title = typeof data.title === 'string' ? data.title : 'Captured';
    return {
      eventType: 'captured',
      title: 'Captured',
      body: title,
      metadata: { source: data.source ?? 'capture' },
    };
  }
  if (status === 'done') {
    return { eventType: 'completed', title: 'Completed', body: 'Marked done.' };
  }
  if ((status === 'active' || status === 'confirmed') && before?.status === 'done') {
    return { eventType: 'reopened', title: 'Reopened', body: 'Moved back to active work.' };
  }
  if ((status === 'active' || status === 'confirmed') && before?.status === 'proposed') {
    return { eventType: 'confirmed', title: 'Confirmed', body: 'Promoted from capture inbox to active work.' };
  }
  if (status === 'proposed') {
    return { eventType: 'reopened', title: 'Reopened', body: 'Moved back to the capture inbox.' };
  }
  const changes = semanticTaskChanges(before, data);
  const changed = changes.map((change) => change.field);
  if (changed.length === 0) return null;
  const first = changes[0]!;
  const rawChanges = Object.fromEntries(changes.map((change) => [
    change.field,
    {
      before: boundedMetadataValue(change.before),
      after: boundedMetadataValue(change.after),
    },
  ]));
  return {
    eventType: 'updated',
    title: changes.length === 1 ? first.title : 'Updated task structure',
    body: changes.length === 1
      ? first.body
      : changes.slice(0, 5).map((change) => change.title).join(' · '),
    metadata: { changed_columns: changed, raw_changes: rawChanges },
  };
}

/**
 * Apply one CRUD op, owner-scoped. Cross-owner ops are denied by the `owner_id` filter, which
 * makes them a silent no-op rather than an error: throwing here would roll back the whole upload
 * batch and wedge PowerSync's retry loop (the failure mode behind the earlier confirm-revert bug).
 * The security guarantee is structural — a client can never overwrite or delete a row it does not
 * own — without making sync brittle.
 */
async function applyOp(client: pg.PoolClient, op: CrudOp, ownerId: string): Promise<boolean> {
  const table = op.type;
  if (!ALLOWED_COLUMNS[table]) {
    if (READ_ONLY_SYNC_TABLES.has(table)) return false;
    throw new Error(`table not allowed: ${table}`);
  }

  if (table === 'task_attachments') {
    return applyAttachmentOp(client, op, ownerId);
  }

  if (op.op === 'DELETE') {
    if (table === 'tasks') await markLinkedAgentProposals(client, ownerId, op.id, 'rejected', false);
    const result = await client.query(`DELETE FROM ${table} WHERE id = $1 AND owner_id = $2`, [op.id, ownerId]);
    return (result.rowCount ?? 0) > 0;
  }

  // Identity fields are forced server-side: the client can never set a foreign owner.
  const data = sanitize(table, { ...(op.data ?? {}), id: op.id, owner_id: ownerId });

  if (op.op === 'PUT') {
    const cols = Object.keys(data);
    const vals = Object.values(data);
    const placeholders = cols.map((_, i) => `$${i + 1}`);
    // owner_id is immutable on update; the WHERE guard prevents overwriting another user's row.
    const updates = cols
      .filter((c) => c !== 'id' && c !== 'owner_id')
      .map((c) => `${c} = EXCLUDED.${c}`);
    const ownerParam = `$${vals.length + 1}`;
    const sql =
      `INSERT INTO ${table} (${cols.join(', ')}) VALUES (${placeholders.join(', ')}) ` +
      `ON CONFLICT (id) DO UPDATE SET ${updates.join(', ')} ` +
      `WHERE ${table}.owner_id = ${ownerParam}`;
    const result = await client.query(sql, [...vals, ownerId]);
    const applied = (result.rowCount ?? 0) > 0;
    if (applied && table === 'tasks') await markTaskProposalDecision(client, ownerId, op.id, data);
    return applied;
  }

  if (op.op === 'PATCH') {
    const cols = Object.keys(data).filter((c) => c !== 'id' && c !== 'owner_id');
    if (cols.length === 0) return false;
    const setClause = cols.map((c, i) => `${c} = $${i + 1}`).join(', ');
    const vals = cols.map((c) => data[c]);
    vals.push(op.id, ownerId);
    const result = await client.query(
      `UPDATE ${table} SET ${setClause} WHERE id = $${vals.length - 1} AND owner_id = $${vals.length}`,
      vals
    );
    const applied = (result.rowCount ?? 0) > 0;
    if (applied && table === 'tasks') await markTaskProposalDecision(client, ownerId, op.id, data);
    return applied;
  }
  return false;
}

async function applyAttachmentOp(client: pg.PoolClient, op: CrudOp, ownerId: string): Promise<boolean> {
  if (op.op === 'DELETE') {
    const result = await client.query(
      `DELETE FROM public.task_attachments WHERE id = $1 AND owner_id = $2`,
      [op.id, ownerId]
    );
    return (result.rowCount ?? 0) > 0;
  }

  if (op.op !== 'PUT') return false;
  const data = sanitize('task_attachments', { ...(op.data ?? {}), id: op.id, owner_id: ownerId });
  const valid = validateAttachmentData(data);
  if (!valid) return false;

  const task = await client.query(
    `SELECT 1 FROM public.tasks WHERE id = $1 AND owner_id = $2 LIMIT 1`,
    [valid.task_id, ownerId]
  );
  if ((task.rowCount ?? 0) === 0) return false;

  const createdAt = valid.created_at ?? new Date().toISOString();
  const result = await client.query(
    `INSERT INTO public.task_attachments
       (id, owner_id, task_id, filename, mime_type, byte_size, preview_data_url, created_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     ON CONFLICT (id) DO UPDATE
       SET filename = EXCLUDED.filename,
           mime_type = EXCLUDED.mime_type,
           byte_size = EXCLUDED.byte_size,
           preview_data_url = EXCLUDED.preview_data_url
     WHERE public.task_attachments.owner_id = $2
       AND public.task_attachments.task_id = $3`,
    [
      op.id,
      ownerId,
      valid.task_id,
      valid.filename,
      valid.mime_type,
      valid.byte_size,
      valid.preview_data_url,
      createdAt,
    ]
  );
  return (result.rowCount ?? 0) > 0;
}

async function markLinkedAgentProposals(
  client: pg.PoolClient,
  ownerId: string,
  taskId: string,
  status: 'accepted' | 'rejected',
  applied: boolean
): Promise<void> {
  const checkpointStatus = status === 'accepted' ? 'approved' : 'rejected';
  await client.query(
    `UPDATE public.agent_proposals
        SET status = $3,
            decided_at = COALESCE(decided_at, now()),
            applied_at = CASE WHEN $4 THEN COALESCE(applied_at, now()) ELSE applied_at END,
            updated_at = now()
      WHERE owner_id = $1
        AND task_id = $2
        AND status = 'pending'`,
    [ownerId, taskId, status, applied]
  );
  await updateLinkedAgentCheckpointsBestEffort(client, ownerId, taskId, checkpointStatus);
}

async function updateLinkedAgentCheckpointsBestEffort(
  client: pg.PoolClient,
  ownerId: string,
  taskId: string,
  status: 'approved' | 'rejected'
): Promise<void> {
  await client.query('SAVEPOINT agent_checkpoint_decision');
  try {
    const exists = await client.query(`SELECT to_regclass('public.agent_checkpoints') AS table_name`);
    if (exists.rows[0]?.table_name) {
      await client.query(
        `UPDATE public.agent_checkpoints
            SET status = $3,
                decided_at = COALESCE(decided_at, now()),
                updated_at = now()
          WHERE owner_id = $1
            AND task_id = $2
            AND status = 'waiting'`,
        [ownerId, taskId, status]
      );
    }
    await client.query('RELEASE SAVEPOINT agent_checkpoint_decision');
  } catch (err) {
    await client.query('ROLLBACK TO SAVEPOINT agent_checkpoint_decision').catch(() => {});
    await client.query('RELEASE SAVEPOINT agent_checkpoint_decision').catch(() => {});
    console.warn('checkpoint decision update skipped:', String(err));
  }
}

async function markTaskProposalDecision(
  client: pg.PoolClient,
  ownerId: string,
  taskId: string,
  data: Record<string, unknown>
): Promise<void> {
  const status = typeof data.status === 'string' ? data.status : null;
  if (status === 'active' || status === 'confirmed') {
    await markLinkedAgentProposals(client, ownerId, taskId, 'accepted', true);
  } else if (status === 'cancelled') {
    await markLinkedAgentProposals(client, ownerId, taskId, 'rejected', false);
  }
}

/**
 * Lightweight capture ingestion for out-of-process clients (iOS Share Extension, Siri/Shortcuts
 * App Intents, the macOS hotkey when run headless). These cannot safely open the app's PowerSync
 * SQLite DB, so they POST a raw capture here and the row syncs back to every client as `proposed`.
 *
 * Idempotent on the client-generated `id`. Always forced to status=proposed and to the caller's
 * own `owner_id` — extensions can never create or mutate a real todo, or write for another user.
 */
const CAPTURE_SOURCES = new Set(['share-extension', 'app-intent', 'mac-hotkey', 'capture', 'siri']);

app.post('/api/capture', requireAuth, async (req: AuthedRequest, res: Response) => {
  const body = req.body ?? {};
  const id: string = typeof body.id === 'string' && body.id ? body.id : randomUUID();
  const rawText: string = (body.raw_text ?? body.title ?? '').toString().trim();
  const url: string | null = typeof body.url === 'string' && body.url ? body.url : null;
  const source: string = CAPTURE_SOURCES.has(body.source) ? body.source : 'capture';
  const parentTaskId: string | null =
    typeof body.parent_task_id === 'string' && body.parent_task_id ? body.parent_task_id : null;

  const title = rawText || url || '';
  if (!title) return res.status(400).json({ ok: false, error: 'empty capture' });

  const notes = url && rawText ? url : null; // keep the URL as context when there's also text

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query(
      `INSERT INTO public.tasks (id, owner_id, parent_task_id, title, notes, status, source)
       VALUES ($1, $2, $3, $4, $5, 'proposed', $6)
       ON CONFLICT (id) DO NOTHING
       RETURNING id`,
      [id, req.ownerId, parentTaskId, title, notes, source]
    );
    if ((result.rowCount ?? 0) > 0) {
      await recordTaskEvent(client, {
        ownerId: req.ownerId!,
        taskId: id,
        actor: source === 'capture' ? 'api' : 'system',
        eventType: 'captured',
        title: 'Captured',
        body: title,
        metadata: { source, has_url: Boolean(url), parent_task_id: parentTaskId },
        idempotencyKey: `capture:${id}`,
      });
    }
    await client.query('COMMIT');
    res.json({ ok: true, id, created: (result.rowCount ?? 0) > 0 });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('capture failed:', err);
    res.status(500).json({ ok: false, error: String(err) });
  } finally {
    client.release();
  }
});

app.post('/api/tasks/:id/comments', requireAuth, async (req: AuthedRequest, res: Response) => {
  const taskId = req.params.id;
  if (!UUID_RE.test(taskId)) {
    return res.status(400).json({ ok: false, error: 'valid task id is required' });
  }
  const body = typeof req.body?.body === 'string' ? req.body.body.trim() : '';
  if (!body) return res.status(400).json({ ok: false, error: 'comment body is required' });
  if (body.length > 2000) return res.status(400).json({ ok: false, error: 'comment body is too long' });
  const requestId = typeof req.body?.request_id === 'string' && UUID_RE.test(req.body.request_id)
    ? req.body.request_id
    : randomUUID();
  const ownerId = req.ownerId!;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const task = await client.query(
      `SELECT id FROM public.tasks WHERE id = $1 AND owner_id = $2 LIMIT 1`,
      [taskId, ownerId]
    );
    if ((task.rowCount ?? 0) === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ ok: false, error: 'task not found' });
    }
    await recordTaskEvent(client, {
      ownerId,
      taskId,
      actor: 'user',
      eventType: 'commented',
      title: 'Commented',
      body,
      metadata: { request_id: requestId, source: 'web' },
      idempotencyKey: requestId,
    });
    await client.query('COMMIT');
    return res.status(201).json({ ok: true, request_id: requestId });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('comment failed:', err);
    return res.status(500).json({ ok: false, error: 'comment failed' });
  } finally {
    client.release();
  }
});

app.post('/api/tasks/:id/agent-handoff', requireAuth, async (req: AuthedRequest, res: Response) => {
  const taskId = req.params.id;
  if (!UUID_RE.test(taskId)) {
    return res.status(400).json({ ok: false, error: 'valid task id is required' });
  }
  const input = parseAgentHandoffInput(req.body);
  if (!input) {
    return res.status(400).json({ ok: false, error: 'mode must be research or attempt' });
  }

  const ownerId = req.ownerId!;
  const requestId = agentHandoffRequestId({ ownerId, taskId, mode: input.mode, instructions: input.instructions });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const task = await client.query(
      `SELECT id, title, status
         FROM public.tasks
        WHERE id = $1 AND owner_id = $2
        LIMIT 1`,
      [taskId, ownerId]
    );
    if ((task.rowCount ?? 0) === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ ok: false, error: 'task not found' });
    }
    const taskTitle = String(task.rows[0]?.title ?? '');
    const modeLabel = input.mode === 'attempt' ? 'AI attempt requested' : 'AI research requested';
    await recordTaskEvent(client, {
      ownerId,
      taskId,
      actor: 'user',
      eventType: 'agent_requested',
      title: modeLabel,
      body: input.instructions ?? (
        input.mode === 'attempt'
          ? 'Try to work out the next safe execution step before asking for approval.'
          : 'Research context and propose the next useful action.'
      ),
      metadata: {
        request_id: requestId,
        mode: input.mode,
        instructions: input.instructions,
        task_title: taskTitle.slice(0, 160),
      },
      idempotencyKey: requestId,
    });
    await client.query('COMMIT');
    return res.status(202).json({ ok: true, request_id: requestId });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('agent handoff request failed:', err);
    return res.status(500).json({ ok: false, error: 'agent handoff failed' });
  } finally {
    client.release();
  }
});

app.post('/api/agent/proposals/:id/decision', requireAuth, async (req: AuthedRequest, res: Response) => {
  const proposalId = req.params.id;
  if (!UUID_RE.test(proposalId)) {
    return res.status(400).json({ ok: false, error: 'valid proposal id is required' });
  }

  const decision = parseAgentProposalDecision(req.body?.decision);
  if (!decision) return res.status(400).json({ ok: false, error: 'decision must be accepted or rejected' });

  let resumePayload: string | null;
  try {
    resumePayload = serializeResumePayload(req.body?.resume_payload);
  } catch (err) {
    return res.status(400).json({ ok: false, error: String(err instanceof Error ? err.message : err) });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const outcome = await applyAgentProposalDecision(client, req.ownerId!, proposalId, decision, resumePayload);
    await client.query('COMMIT');
    if (outcome === 'not_found') return res.status(404).json({ ok: false, error: 'proposal not found' });
    if (outcome === 'not_pending') return res.status(409).json({ ok: false, error: 'proposal already decided' });
    res.json({ ok: true, decided: true, decision });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('proposal decision failed:', err);
    res.status(500).json({ ok: false, error: 'proposal decision failed' });
  } finally {
    client.release();
  }
});

app.put('/api/data', requireAuth, async (req: AuthedRequest, res: Response) => {
  const ops: CrudOp[] = req.body?.ops ?? [];
  const ownerId = req.ownerId!;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const op of ops) {
      const before = op.type === 'tasks'
        ? await readTaskEventState(client, ownerId, op.id)
        : null;
      const applied = await applyOp(client, op, ownerId);
      const event = taskEventForOp(op, applied, before);
      if (event) {
        await recordTaskEvent(client, {
          ...event,
          ownerId,
          taskId: op.id,
          actor: 'user',
          idempotencyKey: `upload:${op.type}:${op.op}:${op.id}:${stableJSON(op.data ?? {})}`,
        });
      }
    }
    await client.query('COMMIT');
    res.json({ ok: true, applied: ops.length });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('upload failed:', err);
    res.status(500).json({ ok: false, error: String(err) });
  } finally {
    client.release();
  }
});

await ensureAuthSchema(pool);

app.listen(PORT, () => {
  console.log(`capture-backend listening on :${PORT} (multi-user)`);
});
