import pg from 'pg';
import { enrich } from './enrich.js';

/**
 * Capture enrichment worker.
 *
 * Capture-first contract: the client writes a `proposed` row instantly with a cheap on-device
 * suggestion (suggestion_source='on-device'). This worker runs in the background, computes a
 * richer suggestion, and patches the suggestion_* fields so the confirm card updates live.
 *
 * It NEVER changes `status`, `title`, or the real `due_at`/`category` — the human still confirms
 * the structure before anything becomes a real todo.
 */

const DATABASE_URI = process.env.WORKER_DATABASE_URI ?? process.env.BACKEND_DATABASE_URI!;
const POLL_MS = Number(process.env.ENRICH_POLL_MS ?? 2000);
const BATCH = Number(process.env.ENRICH_BATCH ?? 20);
const RUN_ONCE = process.env.ENRICH_RUN_ONCE === '1';

const pool = new pg.Pool({ connectionString: DATABASE_URI });

// Claim proposed rows that haven't yet had a server/LLM pass. on-device + null are upgradeable.
const SELECT_SQL = `
  SELECT id, title
  FROM public.tasks
  WHERE status = 'proposed'
    AND coalesce(suggestion_source, 'on-device') NOT IN ('server', 'llm')
  ORDER BY created_at ASC
  LIMIT $1
`;

const UPDATE_SQL = `
  UPDATE public.tasks
  SET suggested_due_at      = $2,
      suggested_category    = $3,
      suggestion_confidence = $4,
      suggestion_source     = $5,
      updated_at            = now()
  WHERE id = $1
    AND status = 'proposed'
`;

async function tick(): Promise<number> {
  const { rows } = await pool.query(SELECT_SQL, [BATCH]);
  if (rows.length === 0) return 0;

  let enriched = 0;
  for (const row of rows) {
    try {
      const e = await enrich(row.title);
      const res = await pool.query(UPDATE_SQL, [
        row.id,
        e.suggestedDueAt,
        e.suggestedCategory,
        e.confidence,
        e.source
      ]);
      if (res.rowCount && res.rowCount > 0) {
        enriched += 1;
        console.log(
          `[worker] enriched ${row.id} -> category=${e.suggestedCategory ?? '∅'} ` +
            `due=${e.suggestedDueAt ?? '∅'} conf=${e.confidence.toFixed(2)} src=${e.source}`
        );
      }
    } catch (err) {
      console.error(`[worker] failed to enrich ${row.id}:`, String(err));
    }
  }
  return enriched;
}

async function main() {
  console.log(
    `[worker] capture enrichment worker up. poll=${POLL_MS}ms batch=${BATCH} ` +
      `llm=${process.env.OPENAI_API_KEY ? 'on' : 'off'} once=${RUN_ONCE}`
  );

  if (RUN_ONCE) {
    const n = await tick();
    console.log(`[worker] one-shot pass enriched ${n} row(s).`);
    await pool.end();
    return;
  }

  // Simple poll loop. Sequential ticks; never overlap. Cheap and robust for a single-user system.
  for (;;) {
    try {
      await tick();
    } catch (err) {
      console.error('[worker] tick error:', String(err));
    }
    await new Promise((r) => setTimeout(r, POLL_MS));
  }
}

const shutdown = async () => {
  console.log('[worker] shutting down.');
  await pool.end().catch(() => {});
  process.exit(0);
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

main().catch((err) => {
  console.error('[worker] fatal:', err);
  process.exit(1);
});
