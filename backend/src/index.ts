import express, { type Request, type Response, type NextFunction } from 'express';
import cors from 'cors';
import pg from 'pg';
import { SignJWT } from 'jose';
import { randomUUID } from 'crypto';
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
} from './auth.js';

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

function sanitize(table: string, data: Record<string, unknown>): Record<string, unknown> {
  const allowed = ALLOWED_COLUMNS[table];
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(data)) {
    if (allowed.has(k)) out[k] = v;
  }
  return out;
}

/**
 * Apply one CRUD op, owner-scoped. Cross-owner ops are denied by the `owner_id` filter, which
 * makes them a silent no-op rather than an error: throwing here would roll back the whole upload
 * batch and wedge PowerSync's retry loop (the failure mode behind the earlier confirm-revert bug).
 * The security guarantee is structural — a client can never overwrite or delete a row it does not
 * own — without making sync brittle.
 */
async function applyOp(client: pg.PoolClient, op: CrudOp, ownerId: string): Promise<void> {
  const table = op.type;
  if (!ALLOWED_COLUMNS[table]) throw new Error(`table not allowed: ${table}`);

  if (op.op === 'DELETE') {
    await client.query(`DELETE FROM ${table} WHERE id = $1 AND owner_id = $2`, [op.id, ownerId]);
    return;
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
    await client.query(sql, [...vals, ownerId]);
    return;
  }

  if (op.op === 'PATCH') {
    const cols = Object.keys(data).filter((c) => c !== 'id' && c !== 'owner_id');
    if (cols.length === 0) return;
    const setClause = cols.map((c, i) => `${c} = $${i + 1}`).join(', ');
    const vals = cols.map((c) => data[c]);
    vals.push(op.id, ownerId);
    await client.query(
      `UPDATE ${table} SET ${setClause} WHERE id = $${vals.length - 1} AND owner_id = $${vals.length}`,
      vals
    );
    return;
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

  const title = rawText || url || '';
  if (!title) return res.status(400).json({ ok: false, error: 'empty capture' });

  const notes = url && rawText ? url : null; // keep the URL as context when there's also text

  try {
    const result = await pool.query(
      `INSERT INTO public.tasks (id, owner_id, title, notes, status, source)
       VALUES ($1, $2, $3, $4, 'proposed', $5)
       ON CONFLICT (id) DO NOTHING
       RETURNING id`,
      [id, req.ownerId, title, notes, source]
    );
    res.json({ ok: true, id, created: (result.rowCount ?? 0) > 0 });
  } catch (err) {
    console.error('capture failed:', err);
    res.status(500).json({ ok: false, error: String(err) });
  }
});

app.put('/api/data', requireAuth, async (req: AuthedRequest, res: Response) => {
  const ops: CrudOp[] = req.body?.ops ?? [];
  const ownerId = req.ownerId!;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const op of ops) await applyOp(client, op, ownerId);
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

app.listen(PORT, () => {
  console.log(`capture-backend listening on :${PORT} (multi-user)`);
});
