import pg from 'pg';
import { createHash } from 'crypto';
import { enrich } from './enrich.js';
import { discoverTaskContext, type TaskDiscovery } from './discovery.js';
import { learnCategoryHints, type CategoryHints, type HistoricalTask } from './historyLearning.js';

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
  SELECT id, owner_id, title
  FROM public.tasks
  WHERE status = 'proposed'
    AND coalesce(suggestion_source, 'on-device') NOT IN ('server', 'llm')
  ORDER BY created_at ASC
  LIMIT $1
`;

const HISTORY_SQL = `
  SELECT owner_id, title, category
  FROM public.tasks
  WHERE owner_id = ANY($1::uuid[])
    AND status IN ('active', 'done')
    AND category IS NOT NULL
  ORDER BY COALESCE(confirmed_at, completed_at, updated_at, created_at) DESC
  LIMIT 500
`;

function deterministicUuid(input: string): string {
  const chars = createHash('sha256').update(input).digest('hex').slice(0, 32).split('');
  chars[12] = '5';
  chars[16] = ((Number.parseInt(chars[16], 16) & 0x3) | 0x8).toString(16);
  const h = chars.join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

function boundedJSON(value: Record<string, unknown>, maxBytes: number): string {
  const encoded = JSON.stringify(value);
  return Buffer.byteLength(encoded, 'utf8') <= maxBytes ? encoded : JSON.stringify({ truncated: true });
}

function metadataJSON(value: Record<string, unknown>): string {
  return boundedJSON(value, 4096);
}

async function recordEnrichmentEvent(
  taskId: string,
  ownerId: string,
  title: string,
  e: Awaited<ReturnType<typeof enrich>>
): Promise<void> {
  const eventId = deterministicUuid(
    `${ownerId}:${taskId}:enriched:${e.source}:${e.suggestedDueAt ?? ''}:${e.suggestedCategory ?? ''}:${e.confidence}`
  );
  await pool.query(
    `INSERT INTO public.task_events
       (id, owner_id, task_id, actor, event_type, title, body, metadata)
     VALUES ($1, $2, $3, 'worker', 'enriched', $4, $5, $6)
     ON CONFLICT (id) DO NOTHING`,
    [
      eventId,
      ownerId,
      taskId,
      e.source === 'llm' ? 'AI organised this task' : 'Auto-organisation updated',
      enrichmentBody(e),
      metadataJSON({
        source: e.source,
        suggested_due_at: e.suggestedDueAt,
        suggested_category: e.suggestedCategory,
        suggested_priority: e.suggestedPriority,
        suggested_tags: e.suggestedTags,
        recurrence: e.recurrence,
        confidence: e.confidence,
        title_sample: title.slice(0, 160),
      }),
    ]
  );
}

function enrichmentBody(e: Awaited<ReturnType<typeof enrich>>): string {
  const parts = [
    e.suggestedCategory ? `category ${e.suggestedCategory}` : null,
    e.suggestedDueAt ? `due ${e.suggestedDueAt}` : null,
    e.suggestedPriority !== null ? `priority ${e.suggestedPriority}` : null,
    e.suggestedTags.length > 0 ? `tags ${e.suggestedTags.join(', ')}` : null,
    e.recurrence ? `recurs ${e.recurrence}` : null,
  ].filter(Boolean);
  return `Suggested ${parts.length > 0 ? parts.join(' · ') : 'no structure changes'}.`;
}

async function recordAgentProposal(
  taskId: string,
  ownerId: string,
  title: string,
  e: Awaited<ReturnType<typeof enrich>>
): Promise<void> {
  const proposalId = deterministicUuid(`${ownerId}:${taskId}:agent-proposal:enrichment`);
  const payload = {
    task_id: taskId,
    title,
    suggested_due_at: e.suggestedDueAt,
    suggested_category: e.suggestedCategory,
    suggested_priority: e.suggestedPriority,
    suggested_tags: e.suggestedTags,
    recurrence: e.recurrence,
  };
  const provenance = {
    source: e.source,
    worker: 'capture-enrichment',
    title_sample: title.slice(0, 160),
  };
  await pool.query(
    `INSERT INTO public.agent_proposals
       (id, owner_id, task_id, proposal_type, status, title, body, payload, provenance, confidence, source)
     VALUES ($1, $2, $3, 'task_update', 'pending', $4, $5, $6, $7, $8, $9)
     ON CONFLICT (id) DO UPDATE
       SET title = EXCLUDED.title,
           body = EXCLUDED.body,
           payload = EXCLUDED.payload,
           provenance = EXCLUDED.provenance,
           confidence = EXCLUDED.confidence,
           source = EXCLUDED.source,
           updated_at = now()
     WHERE public.agent_proposals.status = 'pending'`,
    [
      proposalId,
      ownerId,
      taskId,
      e.source === 'llm' ? 'AI enrichment proposal' : 'Auto-organisation proposal',
      enrichmentBody(e),
      boundedJSON(payload, 8192),
      boundedJSON(provenance, 4096),
      e.confidence,
      e.source,
    ]
  );
}

async function recordDiscoveryEvent(
  taskId: string,
  ownerId: string,
  discovery: TaskDiscovery
): Promise<void> {
  const eventId = deterministicUuid(`${ownerId}:${taskId}:enriched:agent-discovery:${discovery.query}`);
  await pool.query(
    `INSERT INTO public.task_events
       (id, owner_id, task_id, actor, event_type, title, body, metadata)
     VALUES ($1, $2, $3, 'agent', 'enriched', $4, $5, $6)
     ON CONFLICT (id) DO NOTHING`,
    [
      eventId,
      ownerId,
      taskId,
      'Agent discovery prepared',
      discoveryBody(discovery),
      metadataJSON({
        source: 'agent-discovery',
        query: discovery.query,
        location: discovery.location,
        web: discovery.web,
        next_actions: discovery.nextActions,
        confidence: discovery.confidence,
      }),
    ]
  );
}

async function recordDiscoveryProposal(
  taskId: string,
  ownerId: string,
  discovery: TaskDiscovery
): Promise<void> {
  const proposalId = deterministicUuid(`${ownerId}:${taskId}:agent-proposal:discovery:${discovery.query}`);
  const payload = {
    task_id: taskId,
    action_type: 'task_context_lookup',
    query: discovery.query,
    location: discovery.location,
    web: discovery.web,
    next_actions: discovery.nextActions,
  };
  const provenance = {
    source: 'agent-discovery',
    worker: 'capture-enrichment',
    location_source: discovery.location.source,
    web_source: discovery.web.source,
  };
  await pool.query(
    `INSERT INTO public.agent_proposals
       (id, owner_id, task_id, proposal_type, status, title, body, payload, provenance, confidence, source)
     VALUES ($1, $2, $3, 'action', 'pending', $4, $5, $6, $7, $8, 'agent-discovery')
     ON CONFLICT (id) DO UPDATE
       SET title = EXCLUDED.title,
           body = EXCLUDED.body,
           payload = EXCLUDED.payload,
           provenance = EXCLUDED.provenance,
           confidence = EXCLUDED.confidence,
           source = EXCLUDED.source,
           updated_at = now()
     WHERE public.agent_proposals.status = 'pending'`,
    [
      proposalId,
      ownerId,
      taskId,
      `Discovery for ${discovery.title}`.slice(0, 160),
      discoveryBody(discovery),
      boundedJSON(payload, 8192),
      boundedJSON(provenance, 4096),
      discovery.confidence,
    ]
  );
}

function discoveryBody(discovery: TaskDiscovery): string {
  const results = discovery.web.results
    .slice(0, 3)
    .map((result, index) => `${index + 1}. ${result.title}${result.url ? ` — ${result.url}` : ''}`)
    .join('\n');
  const actions = discovery.nextActions.map((action) => `- ${action}`).join('\n');
  const parts = [
    `Query: ${discovery.query}`,
    discovery.location.source === 'env'
      ? `Location: ${discovery.location.label ?? `${discovery.location.latitude}, ${discovery.location.longitude}`}`
      : 'Location: unavailable',
    results ? `Top results:\n${results}` : `Web: ${discovery.web.source}`,
    `Next actions:\n${actions}`,
  ];
  return parts.join('\n\n').slice(0, 2000);
}

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
  const ownerIds = [...new Set(rows.map((row) => row.owner_id as string))];
  const historyByOwner = new Map<string, CategoryHints>();
  if (ownerIds.length > 0) {
    const history = await pool.query(HISTORY_SQL, [ownerIds]);
    const grouped = new Map<string, HistoricalTask[]>();
    for (const row of history.rows) {
      const ownerId = row.owner_id as string;
      const items = grouped.get(ownerId) ?? [];
      items.push({ title: row.title as string, category: row.category as string | null });
      grouped.set(ownerId, items);
    }
    for (const [ownerId, items] of grouped) {
      historyByOwner.set(ownerId, learnCategoryHints(items));
    }
  }

  let enriched = 0;
  for (const row of rows) {
    try {
      const e = await enrich(row.title, new Date(), historyByOwner.get(row.owner_id) ?? {});
      const res = await pool.query(UPDATE_SQL, [
        row.id,
        e.suggestedDueAt,
        e.suggestedCategory,
        e.confidence,
        e.source
      ]);
      if (res.rowCount && res.rowCount > 0) {
        await recordEnrichmentEvent(row.id, row.owner_id, row.title, e);
        await recordAgentProposal(row.id, row.owner_id, row.title, e);
        const discovery = await discoverTaskContext({
          id: row.id,
          ownerId: row.owner_id,
          title: row.title,
        });
        if (discovery) {
          await recordDiscoveryEvent(row.id, row.owner_id, discovery);
          await recordDiscoveryProposal(row.id, row.owner_id, discovery);
        }
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
