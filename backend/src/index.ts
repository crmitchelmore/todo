import express, { type Request, type Response, type NextFunction } from 'express';
import cors from 'cors';
import pg from 'pg';
import { SignJWT } from 'jose';
import { createHash, randomUUID } from 'crypto';
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
} from './auth.js';
import { sendEmailBestEffort, loginCodeEmail, resetCodeEmail } from './mailer.js';

/**
 * Capture backend connector (multi-user, email + password auth).
 *
 *  - POST /api/auth/register Create an account (email + password) and return a session token.
 *  - POST /api/auth/login    Exchange email + password for an opaque session token.
 *  - POST /api/auth/logout   Revoke the caller's session.
 *  - GET  /api/auth/keys     JWKS so the PowerSync service can verify the per-user sync tokens.
 *  - GET  /api/auth/token    Mint a short-lived per-user RS256 JWT + the PowerSync endpoint URL.
 *  - PUT  /api/data          Apply a batch of client CRUD ops to Postgres (owner-scoped write path).
 *  - POST /api/capture       Lightweight ingest for out-of-process surfaces (extensions/intents).
 */

const PORT = Number(process.env.BACKEND_PORT ?? 6060);
const DATABASE_URI = process.env.BACKEND_DATABASE_URI!;
const JWT_ISSUER = process.env.JWT_ISSUER ?? 'capture';
const JWT_AUDIENCE = process.env.JWT_AUDIENCE ?? 'powersync';
const POWERSYNC_URL = process.env.POWERSYNC_PUBLIC_URL ?? 'http://localhost:8080';

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
    'id', 'owner_id', 'title', 'notes', 'status', 'category', 'tags', 'due_at', 'priority',
    'suggested_due_at', 'suggested_category', 'suggestion_confidence', 'suggestion_source',
    'source', 'created_at', 'updated_at', 'confirmed_at', 'completed_at'
  ]),
  tags: new Set([
    'id', 'owner_id', 'name', 'color', 'created_at', 'updated_at'
  ])
};

app.get('/api/health', (_req, res) => res.json({ ok: true }));

app.get('/api/auth/keys', (_req, res) => {
  res.json({ keys: [publicJwk] });
});

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
    const sessionToken = await createSession(pool, userId, client);
    res.json({ ok: true, session_token: sessionToken, user_id: userId });
  } catch (err) {
    console.error('login failed:', err);
    res.status(500).json({ ok: false, error: 'login failed' });
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
    const sessionToken = await createSession(pool, userId, client);
    res.json({ ok: true, session_token: sessionToken, user_id: userId });
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
    const sessionToken = await createSession(pool, result.userId, client);
    res.json({ ok: true, session_token: sessionToken, user_id: result.userId });
  } catch (err) {
    console.error('password reset failed:', err);
    res.status(500).json({ ok: false, error: 'reset failed' });
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

type TaskEventType = 'captured' | 'confirmed' | 'updated' | 'completed' | 'reopened' | 'deleted' | 'enriched';

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

function taskEventForOp(op: CrudOp, applied: boolean): Omit<TaskEventInput, 'ownerId' | 'actor' | 'taskId' | 'idempotencyKey'> | null {
  if (!applied || op.type !== 'tasks' || op.op === 'DELETE') return null;
  const data = op.data ?? {};
  const status = typeof data.status === 'string' ? data.status : null;
  if (status === 'done') {
    return { eventType: 'completed', title: 'Completed', body: 'Marked done.' };
  }
  if (status === 'active' || status === 'confirmed') {
    return { eventType: 'confirmed', title: 'Confirmed', body: 'Promoted from capture inbox to active work.' };
  }
  if (status === 'proposed') {
    return { eventType: 'reopened', title: 'Reopened', body: 'Moved back to the capture inbox.' };
  }
  const changed = Object.keys(data).filter((k) => ALLOWED_COLUMNS.tasks.has(k) && k !== 'id' && k !== 'owner_id');
  if (changed.length === 0) return null;
  return {
    eventType: 'updated',
    title: 'Updated',
    body: `Changed ${changed.slice(0, 6).join(', ')}.`,
    metadata: { changed },
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
  if (!ALLOWED_COLUMNS[table]) throw new Error(`table not allowed: ${table}`);

  if (op.op === 'DELETE') {
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
    return (result.rowCount ?? 0) > 0;
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
    return (result.rowCount ?? 0) > 0;
  }
  return false;
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

  const title = rawText || url || '';
  if (!title) return res.status(400).json({ ok: false, error: 'empty capture' });

  const notes = url && rawText ? url : null; // keep the URL as context when there's also text

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query(
      `INSERT INTO public.tasks (id, owner_id, title, notes, status, source)
       VALUES ($1, $2, $3, $4, 'proposed', $5)
       ON CONFLICT (id) DO NOTHING
       RETURNING id`,
      [id, req.ownerId, title, notes, source]
    );
    if ((result.rowCount ?? 0) > 0) {
      await recordTaskEvent(client, {
        ownerId: req.ownerId!,
        taskId: id,
        actor: source === 'capture' ? 'api' : 'system',
        eventType: 'captured',
        title: 'Captured',
        body: title,
        metadata: { source, has_url: Boolean(url) },
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

app.put('/api/data', requireAuth, async (req: AuthedRequest, res: Response) => {
  const ops: CrudOp[] = req.body?.ops ?? [];
  const ownerId = req.ownerId!;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const op of ops) {
      const applied = await applyOp(client, op, ownerId);
      const event = taskEventForOp(op, applied);
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
