import express from 'express';
import cors from 'cors';
import pg from 'pg';
import { generateKeyPair, exportJWK, SignJWT, type JWK } from 'jose';

/**
 * Capture backend connector (M1, single dev user).
 *
 * Responsibilities:
 *  - GET  /api/auth/keys   JWKS for the PowerSync service to verify client tokens.
 *  - GET  /api/auth/token  Mint a short-lived RS256 JWT + the PowerSync endpoint URL.
 *  - PUT  /api/data        Apply a batch of client CRUD ops to Postgres (the write path).
 *
 * The keypair is generated at startup (dev convenience) so no secrets are committed.
 */

const PORT = Number(process.env.BACKEND_PORT ?? 6060);
const DATABASE_URI = process.env.BACKEND_DATABASE_URI!;
const JWT_ISSUER = process.env.JWT_ISSUER ?? 'capture-dev';
const JWT_AUDIENCE = process.env.JWT_AUDIENCE ?? 'powersync-dev';
const DEV_USER_ID = process.env.DEV_USER_ID ?? '00000000-0000-0000-0000-000000000001';
const POWERSYNC_URL = process.env.POWERSYNC_PUBLIC_URL ?? 'http://localhost:8080';

const KID = 'capture-dev-key';

// --- Write-path safety: only these tables/columns may be mutated by clients. -----------------
const ALLOWED_COLUMNS: Record<string, Set<string>> = {
  tasks: new Set([
    'id', 'owner_id', 'title', 'notes', 'status', 'category', 'due_at', 'priority',
    'suggested_due_at', 'suggested_category', 'suggestion_confidence', 'suggestion_source',
    'source', 'created_at', 'updated_at', 'confirmed_at', 'completed_at'
  ])
};

const pool = new pg.Pool({ connectionString: DATABASE_URI });

const { publicKey, privateKey } = await generateKeyPair('RS256', { extractable: true });
const publicJwk: JWK = { ...(await exportJWK(publicKey)), kid: KID, alg: 'RS256', use: 'sig' };

const app = express();
app.use(cors());
app.use(express.json({ limit: '5mb' }));

app.get('/api/health', (_req, res) => res.json({ ok: true }));

app.get('/api/auth/keys', (_req, res) => {
  res.json({ keys: [publicJwk] });
});

app.get('/api/auth/token', async (_req, res) => {
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: 'RS256', kid: KID })
    .setSubject(DEV_USER_ID)
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

async function applyOp(client: pg.PoolClient, op: CrudOp): Promise<void> {
  const table = op.type;
  if (!ALLOWED_COLUMNS[table]) throw new Error(`table not allowed: ${table}`);

  if (op.op === 'DELETE') {
    await client.query(`DELETE FROM ${table} WHERE id = $1`, [op.id]);
    return;
  }

  // Force identity fields server-side: client never sets a foreign owner.
  const data = sanitize(table, { ...(op.data ?? {}), id: op.id, owner_id: DEV_USER_ID });

  if (op.op === 'PUT') {
    const cols = Object.keys(data);
    const vals = Object.values(data);
    const placeholders = cols.map((_, i) => `$${i + 1}`);
    const updates = cols
      .filter((c) => c !== 'id')
      .map((c) => `${c} = EXCLUDED.${c}`);
    const sql =
      `INSERT INTO ${table} (${cols.join(', ')}) VALUES (${placeholders.join(', ')}) ` +
      `ON CONFLICT (id) DO UPDATE SET ${updates.join(', ')}`;
    await client.query(sql, vals);
    return;
  }

  if (op.op === 'PATCH') {
    const cols = Object.keys(data).filter((c) => c !== 'id');
    if (cols.length === 0) return;
    const setClause = cols.map((c, i) => `${c} = $${i + 1}`).join(', ');
    const vals = cols.map((c) => data[c]);
    vals.push(op.id);
    await client.query(`UPDATE ${table} SET ${setClause} WHERE id = $${vals.length}`, vals);
    return;
  }
}

app.put('/api/data', async (req, res) => {
  const ops: CrudOp[] = req.body?.ops ?? [];
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const op of ops) await applyOp(client, op);
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
  console.log(`capture-backend listening on :${PORT} (user ${DEV_USER_ID})`);
});
