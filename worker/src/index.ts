import pg from 'pg';
import { createHash } from 'crypto';
import { enrich, type CategorisationRule } from './enrich.js';
import { discoverTaskContext, type TaskDiscovery } from './discovery.js';
import { parseAgentHandoffMetadata, type AgentHandoffRequest } from './handoff.js';
import { runAgentResearch, type AgentResearchBrief } from './handoffResearch.js';
import {
  instructionsFromInterview,
  interviewPromptFor,
  needsInterview,
  parseInterviewResumePayload,
} from './autoResearch.js';
import { interruptForHumanDecision } from './hitl.js';
import {
  localHarnessConfigFromEnv,
  runLocalHarnessAttempt,
  type LocalHarnessConfig,
  type LocalHarnessRunResult,
} from './localHarnessExecutor.js';
import { learnCategoryHints, type CategoryHints, type HistoricalTask } from './historyLearning.js';
import { bestMatch, discoverConfiguredGitHubRepositories, shouldAssociateGitHubProject, type GitHubRepository } from './githubProject.js';
import { compactMemories, loadActiveMemories } from './memories.js';
import { captureException, initObservability, startSpan, wideEvent } from './observability.js';

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
const LOCAL_HARNESS_CONFIG = localHarnessConfigFromEnv();

initObservability();

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

const CATEGORISATION_RULES_SQL = `
  SELECT owner_id, title, instructions, category, tags
  FROM public.categorisation_rules
  WHERE owner_id = ANY($1::uuid[])
    AND enabled = 1
  ORDER BY updated_at DESC, created_at DESC
  LIMIT 1000
`;

const HANDOFF_REQUEST_SQL = `
  SELECT
    req.id AS request_event_id,
    req.owner_id,
    req.task_id,
    req.metadata,
    t.title
  FROM public.task_events req
  JOIN public.tasks t
    ON t.owner_id = req.owner_id
   AND t.id = req.task_id
  WHERE req.event_type = 'agent_requested'
    AND req.metadata IS NOT NULL
    AND (req.metadata::jsonb ->> 'request_id') IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
        FROM public.task_events done
       WHERE done.owner_id = req.owner_id
         AND done.task_id = req.task_id
         AND done.event_type IN ('agent_completed', 'agent_failed')
         AND done.metadata IS NOT NULL
         AND done.metadata::jsonb ->> 'request_id' = req.metadata::jsonb ->> 'request_id'
    )
  ORDER BY req.created_at ASC
  LIMIT $1
`;

const GITHUB_ASSOCIATION_SQL = `
  SELECT id, owner_id, title, category, suggested_category, github_repo
  FROM public.tasks
  WHERE status IN ('proposed', 'active', 'confirmed')
    AND github_repo IS NULL
    AND COALESCE(category, suggested_category) = 'engineering'
  ORDER BY updated_at DESC, created_at DESC
  LIMIT $1
`;

const APPROVED_ATTEMPT_SQL = `
  SELECT
    cp.id AS checkpoint_id,
    cp.owner_id,
    cp.task_id,
    cp.proposal_id,
    cp.thread_id,
    cp.checkpoint_key,
    cp.action_payload,
    cp.resume_payload,
    t.title
  FROM public.agent_checkpoints cp
  JOIN public.tasks t
    ON t.owner_id = cp.owner_id
   AND t.id = cp.task_id
  WHERE cp.status = 'approved'
    AND cp.action_type = 'attempt_task'
  ORDER BY cp.decided_at ASC NULLS LAST, cp.updated_at ASC
  LIMIT $1
`;

const APPROVED_INTERVIEW_SQL = `
  SELECT
    cp.id AS checkpoint_id,
    cp.owner_id,
    cp.task_id,
    cp.proposal_id,
    cp.thread_id,
    cp.checkpoint_key,
    cp.action_payload,
    cp.resume_payload,
    t.title
  FROM public.agent_checkpoints cp
  JOIN public.tasks t
    ON t.owner_id = cp.owner_id
   AND t.id = cp.task_id
  WHERE cp.status = 'approved'
    AND cp.action_type = 'task_interview'
    AND cp.resume_payload IS NOT NULL
  ORDER BY cp.decided_at ASC NULLS LAST, cp.updated_at ASC
  LIMIT $1
`;

interface HandoffRequestRow {
  request_event_id: string;
  owner_id: string;
  task_id: string;
  metadata: string | null;
  title: string;
}

interface GitHubAssociationRow {
  id: string;
  owner_id: string;
  title: string;
  category: string | null;
  suggested_category: string | null;
  github_repo: string | null;
}

interface ApprovedAttemptRow {
  checkpoint_id: string;
  owner_id: string;
  task_id: string;
  proposal_id: string | null;
  thread_id: string;
  checkpoint_key: string;
  action_payload: string;
  resume_payload: string | null;
  title: string;
}

interface ApprovedInterviewRow {
  checkpoint_id: string;
  owner_id: string;
  task_id: string;
  proposal_id: string | null;
  thread_id: string;
  checkpoint_key: string;
  action_payload: string;
  resume_payload: string | null;
  title: string;
}

interface CategorisationRuleRow {
  owner_id: string;
  title: string;
  instructions: string;
  category: string | null;
  tags: string | null;
}

function decodeTags(raw: string | null): string[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw) as unknown;
    return Array.isArray(parsed) ? parsed.filter((tag): tag is string => typeof tag === 'string') : [];
  } catch {
    return [];
  }
}

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
        memories: compactMemories(discovery.memories),
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
    memories: compactMemories(discovery.memories),
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

async function recordGitHubAssociationEvent(
  row: GitHubAssociationRow,
  repo: GitHubRepository
): Promise<void> {
  const eventId = deterministicUuid(`${row.owner_id}:${row.id}:github-project:${repo.fullName}`);
  await pool.query(
    `INSERT INTO public.task_events
       (id, owner_id, task_id, actor, event_type, title, body, metadata)
     VALUES ($1, $2, $3, 'worker', 'enriched', 'Linked GitHub project', $4, $5)
     ON CONFLICT (id) DO NOTHING`,
    [
      eventId,
      row.owner_id,
      row.id,
      `${repo.fullName} — ${repo.url}`,
      metadataJSON({
        source: 'local-work-root',
        github_repo: repo.fullName,
        github_url: repo.url,
        repo_path: repo.path,
        confidence: Math.min(0.95, 0.55 + repo.score / 20),
      }),
    ]
  );
}

async function processGitHubAssociations(): Promise<number> {
  const { rows } = await pool.query<GitHubAssociationRow>(GITHUB_ASSOCIATION_SQL, [BATCH]);
  if (rows.length === 0) return 0;
  const repos = await discoverConfiguredGitHubRepositories();
  if (repos.length === 0) return 0;
  let associated = 0;
  for (const row of rows) {
    if (!shouldAssociateGitHubProject(row)) continue;
    const repo = bestMatch(row.title, repos);
    if (!repo) continue;
    const result = await pool.query(
      `UPDATE public.tasks
          SET github_repo = $3,
              github_url = $4,
              updated_at = now()
        WHERE id = $1
          AND owner_id = $2
          AND github_repo IS NULL`,
      [row.id, row.owner_id, repo.fullName, repo.url]
    );
    if ((result.rowCount ?? 0) === 0) continue;
    await recordGitHubAssociationEvent(row, repo);
    associated += 1;
    console.log(`[worker] associated ${row.id} -> github=${repo.fullName}`);
  }
  return associated;
}

async function recordHandoffCompletionEvent(
  row: HandoffRequestRow,
  request: AgentHandoffRequest,
  discovery: TaskDiscovery,
  brief: AgentResearchBrief
): Promise<void> {
  const eventId = deterministicUuid(`${row.owner_id}:${row.task_id}:agent-completed:${request.requestId}`);
  await pool.query(
    `INSERT INTO public.task_events
       (id, owner_id, task_id, actor, event_type, title, body, metadata)
     VALUES ($1, $2, $3, 'agent', 'agent_completed', $4, $5, $6)
     ON CONFLICT (id) DO NOTHING`,
    [
      eventId,
      row.owner_id,
      row.task_id,
      request.mode === 'attempt' ? 'AI attempt plan ready' : 'AI research ready',
      brief.body,
      metadataJSON({
        request_id: request.requestId,
        mode: request.mode,
        instructions: request.instructions,
        source: 'agent-handoff',
        research_source: brief.source,
        model: brief.model,
        query: discovery.query,
        location: discovery.location,
        memories: compactMemories(discovery.memories),
        web: discovery.web,
        next_actions: brief.nextActions,
        deterministic_next_actions: discovery.nextActions,
        confidence: brief.confidence,
      }),
    ]
  );
}

async function recordHandoffFailureEvent(
  row: HandoffRequestRow,
  request: AgentHandoffRequest | null,
  error: unknown
): Promise<void> {
  const requestId = request?.requestId ?? row.request_event_id;
  const eventId = deterministicUuid(`${row.owner_id}:${row.task_id}:agent-failed:${requestId}`);
  await pool.query(
    `INSERT INTO public.task_events
       (id, owner_id, task_id, actor, event_type, title, body, metadata)
     VALUES ($1, $2, $3, 'agent', 'agent_failed', 'AI handoff failed', $4, $5)
     ON CONFLICT (id) DO NOTHING`,
    [
      eventId,
      row.owner_id,
      row.task_id,
      String(error).slice(0, 2000),
      metadataJSON({
        request_id: requestId,
        mode: request?.mode ?? 'unknown',
        source: 'agent-handoff',
      }),
    ]
  );
}

async function recordHandoffResearchProposal(
  row: HandoffRequestRow,
  request: AgentHandoffRequest,
  discovery: TaskDiscovery,
  brief: AgentResearchBrief
): Promise<void> {
  const proposalId = deterministicUuid(`${row.owner_id}:${row.task_id}:agent-handoff:${request.requestId}:research`);
  await pool.query(
    `INSERT INTO public.agent_proposals
       (id, owner_id, task_id, proposal_type, status, title, body, payload, provenance, confidence, source)
     VALUES ($1, $2, $3, 'task_update', 'pending', $4, $5, $6, $7, $8, 'agent-handoff')
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
      row.owner_id,
      row.task_id,
      request.mode === 'attempt' ? 'AI attempt research brief' : 'AI research brief',
      brief.body,
      boundedJSON({
        task_id: row.task_id,
        request_id: request.requestId,
        action_type: 'task_context_lookup',
        handoff_mode: request.mode,
        instructions: request.instructions,
        research_source: brief.source,
        model: brief.model,
        query: discovery.query,
        location: discovery.location,
        web: discovery.web,
        next_actions: brief.nextActions,
        deterministic_next_actions: discovery.nextActions,
      }, 8192),
      boundedJSON({
        source: 'agent-handoff',
        research_source: brief.source,
        model: brief.model,
        request_event_id: row.request_event_id,
        worker: 'capture-enrichment',
      }, 4096),
      brief.confidence,
    ]
  );
}

function autoResearchRequest(row: { owner_id: string; id: string; title: string }, instructions: string | null = null): AgentHandoffRequest {
  return {
    requestId: deterministicUuid(`${row.owner_id}:${row.id}:auto-research:${instructions ?? ''}`),
    mode: 'research',
    instructions,
  };
}

async function recordAutoResearchCompletionEvent(
  row: { id: string; owner_id: string; title: string },
  request: AgentHandoffRequest,
  discovery: TaskDiscovery,
  brief: AgentResearchBrief
): Promise<void> {
  const eventId = deterministicUuid(`${row.owner_id}:${row.id}:auto-research-completed:${request.requestId}`);
  await pool.query(
    `INSERT INTO public.task_events
       (id, owner_id, task_id, actor, event_type, title, body, metadata)
     VALUES ($1, $2, $3, 'agent', 'agent_completed', 'AI research ready', $4, $5)
     ON CONFLICT (id) DO NOTHING`,
    [
      eventId,
      row.owner_id,
      row.id,
      brief.body,
      metadataJSON({
        request_id: request.requestId,
        mode: 'research',
        source: 'auto-research',
        research_source: brief.source,
        model: brief.model,
        query: discovery.query,
        location: discovery.location,
        memories: compactMemories(discovery.memories),
        web: discovery.web,
        next_actions: brief.nextActions,
        deterministic_next_actions: discovery.nextActions,
        confidence: brief.confidence,
      }),
    ]
  );
}

async function recordAutoResearchProposal(
  row: { id: string; owner_id: string; title: string },
  request: AgentHandoffRequest,
  discovery: TaskDiscovery,
  brief: AgentResearchBrief
): Promise<void> {
  const proposalId = deterministicUuid(`${row.owner_id}:${row.id}:auto-research:${request.requestId}:brief`);
  await pool.query(
    `INSERT INTO public.agent_proposals
       (id, owner_id, task_id, proposal_type, status, title, body, payload, provenance, confidence, source)
     VALUES ($1, $2, $3, 'task_update', 'pending', 'AI research brief', $4, $5, $6, $7, 'auto-research')
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
      row.owner_id,
      row.id,
      brief.body,
      boundedJSON({
        task_id: row.id,
        request_id: request.requestId,
        action_type: 'task_context_lookup',
        handoff_mode: 'research',
        instructions: request.instructions,
        research_source: brief.source,
        model: brief.model,
        query: discovery.query,
        location: discovery.location,
        web: discovery.web,
        next_actions: brief.nextActions,
        deterministic_next_actions: discovery.nextActions,
      }, 8192),
      boundedJSON({
        source: 'auto-research',
        research_source: brief.source,
        model: brief.model,
        worker: 'capture-enrichment',
      }, 4096),
      brief.confidence,
    ]
  );
}

async function recordInterviewPromptGate(
  row: { id: string; owner_id: string; title: string },
  discovery: TaskDiscovery,
  reason: string
): Promise<void> {
  const prompt = interviewPromptFor(discovery, reason);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await interruptForHumanDecision(client, {
      ownerId: row.owner_id,
      taskId: row.id,
      threadId: `task-${row.id}-auto-research`,
      checkpointKey: 'interview:auto-research',
      interruptBefore: 'research_without_context',
      actionType: 'task_interview',
      title: 'Help the agent research this',
      body: prompt.question,
      payload: {
        task_id: row.id,
        request_id: deterministicUuid(`${row.owner_id}:${row.id}:auto-research:interview`),
        question: prompt.question,
        options: prompt.options,
        allow_free_text: prompt.allowFreeText,
        reason: prompt.reason,
        discovery,
      },
      provenance: {
        source: 'auto-research',
        worker: 'capture-enrichment',
      },
      confidence: Math.max(0.2, discovery.confidence),
      source: 'auto-research',
      riskLevel: 'medium',
      reversible: true,
      mutatesExternalState: false,
    });
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

async function recordAttemptApprovalGate(
  row: HandoffRequestRow,
  request: AgentHandoffRequest,
  discovery: TaskDiscovery,
  brief: AgentResearchBrief
): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await interruptForHumanDecision(client, {
      ownerId: row.owner_id,
      taskId: row.task_id,
      threadId: `task-${row.task_id}-${request.requestId}`,
      checkpointKey: `attempt:${request.requestId}`,
      interruptBefore: 'external_action',
      actionType: 'attempt_task',
      title: 'Approve AI attempt plan',
      body: `${brief.body}\n\nApproval records consent for the next agent turn; external execution still needs a local harness on the selected backend computer.`,
      payload: {
        task_id: row.task_id,
        request_id: request.requestId,
        handoff_mode: request.mode,
        instructions: request.instructions,
        discovery,
        research: brief,
      },
      provenance: {
        source: 'agent-handoff',
        research_source: brief.source,
        model: brief.model,
        request_event_id: row.request_event_id,
      },
      confidence: brief.confidence,
      source: 'agent-handoff',
      riskLevel: 'medium',
      reversible: false,
      mutatesExternalState: true,
    });
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

function parseJsonRecord(value: string | null): Record<string, unknown> {
  if (!value) return {};
  try {
    const parsed = JSON.parse(value) as unknown;
    return typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : {};
  } catch {
    return {};
  }
}

function handoffRequestFromActionPayload(payload: Record<string, unknown>): AgentHandoffRequest | null {
  return parseAgentHandoffMetadata({
    request_id: payload.request_id,
    mode: payload.handoff_mode,
    instructions: payload.instructions,
  });
}

async function processApprovedInterviewResponses(): Promise<number> {
  const { rows } = await pool.query<ApprovedInterviewRow>(APPROVED_INTERVIEW_SQL, [BATCH]);
  let processed = 0;
  for (const row of rows) {
    const resume = parseInterviewResumePayload(parseJsonRecord(row.resume_payload));
    if (!resume) {
      await pool.query(
        `UPDATE public.agent_checkpoints
            SET status = 'cancelled',
                updated_at = now()
          WHERE id = $1
            AND owner_id = $2
            AND status = 'approved'
            AND action_type = 'task_interview'`,
        [row.checkpoint_id, row.owner_id]
      );
      continue;
    }

    const requestId = deterministicUuid(`${row.owner_id}:${row.task_id}:auto-interview-response:${row.checkpoint_id}:${resume.answer}`);
    const eventId = deterministicUuid(`${row.owner_id}:${row.task_id}:agent-requested:${requestId}`);
    const instructions = instructionsFromInterview(resume);
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const claim = await client.query(
        `UPDATE public.agent_checkpoints
            SET status = 'resumed',
                resumed_at = COALESCE(resumed_at, now()),
                updated_at = now()
          WHERE id = $1
            AND owner_id = $2
            AND status = 'approved'
            AND action_type = 'task_interview'`,
        [row.checkpoint_id, row.owner_id]
      );
      if ((claim.rowCount ?? 0) === 0) {
        await client.query('ROLLBACK');
        continue;
      }
      await client.query(
        `INSERT INTO public.task_events
           (id, owner_id, task_id, actor, event_type, title, body, metadata)
         VALUES ($1, $2, $3, 'user', 'agent_requested', 'Research context added', $4, $5)
         ON CONFLICT (id) DO NOTHING`,
        [
          eventId,
          row.owner_id,
          row.task_id,
          instructions,
          metadataJSON({
            request_id: requestId,
            mode: 'research',
            instructions,
            source: 'auto-interview',
            checkpoint_id: row.checkpoint_id,
            proposal_id: row.proposal_id,
            selected_option_id: resume.selectedOptionId,
            selected_option_label: resume.selectedOptionLabel,
            has_free_text: Boolean(resume.freeText),
            task_title: row.title.slice(0, 160),
          }),
        ]
      );
      await client.query('COMMIT');
      processed += 1;
      console.log(`[worker] interview response ${row.checkpoint_id} -> task=${row.task_id}`);
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      captureException(err, { op: 'auto_interview_response', checkpoint_id: row.checkpoint_id, task_id: row.task_id });
      throw err;
    } finally {
      client.release();
    }
  }
  return processed;
}

async function claimApprovedAttempt(row: ApprovedAttemptRow): Promise<boolean> {
  const result = await pool.query(
    `UPDATE public.agent_checkpoints
        SET status = 'resumed',
            resumed_at = COALESCE(resumed_at, now()),
            updated_at = now()
      WHERE id = $1
        AND owner_id = $2
        AND status = 'approved'
        AND action_type = 'attempt_task'`,
    [row.checkpoint_id, row.owner_id]
  );
  return (result.rowCount ?? 0) > 0;
}

async function recordLocalHarnessCompletionEvent(
  row: ApprovedAttemptRow,
  request: AgentHandoffRequest,
  result: LocalHarnessRunResult
): Promise<void> {
  const eventId = deterministicUuid(`${row.owner_id}:${row.task_id}:local-harness-completed:${row.checkpoint_id}`);
  await pool.query(
    `INSERT INTO public.task_events
       (id, owner_id, task_id, actor, event_type, title, body, metadata)
     VALUES ($1, $2, $3, 'agent', 'agent_completed', 'Local harness attempt completed', $4, $5)
     ON CONFLICT (id) DO NOTHING`,
    [
      eventId,
      row.owner_id,
      row.task_id,
      result.reply,
      metadataJSON({
        request_id: request.requestId,
        mode: 'attempt',
        source: 'local-harness',
        checkpoint_id: row.checkpoint_id,
        proposal_id: row.proposal_id,
        thread_id: row.thread_id,
        checkpoint_key: row.checkpoint_key,
        harness_kind: result.harnessKind,
        harness_device_id: result.deviceId,
        harness_device_name: result.deviceName,
        harness_run_id: result.runId,
        harness_status: result.status,
        stdout_sample: result.stdout.slice(0, 1200),
      }),
    ]
  );
}

async function recordLocalHarnessFailureEvent(
  row: ApprovedAttemptRow,
  request: AgentHandoffRequest | null,
  error: unknown
): Promise<void> {
  const requestId = request?.requestId ?? row.checkpoint_id;
  const eventId = deterministicUuid(`${row.owner_id}:${row.task_id}:local-harness-failed:${row.checkpoint_id}`);
  await pool.query(
    `INSERT INTO public.task_events
       (id, owner_id, task_id, actor, event_type, title, body, metadata)
     VALUES ($1, $2, $3, 'agent', 'agent_failed', 'Local harness attempt failed', $4, $5)
     ON CONFLICT (id) DO NOTHING`,
    [
      eventId,
      row.owner_id,
      row.task_id,
      String(error).slice(0, 2000),
      metadataJSON({
        request_id: requestId,
        mode: 'attempt',
        source: 'local-harness',
        checkpoint_id: row.checkpoint_id,
        proposal_id: row.proposal_id,
        thread_id: row.thread_id,
        checkpoint_key: row.checkpoint_key,
      }),
    ]
  );
}

async function processApprovedLocalHarnessAttempts(config: LocalHarnessConfig | null = LOCAL_HARNESS_CONFIG): Promise<number> {
  if (!config) return 0;
  const { rows } = await pool.query<ApprovedAttemptRow>(APPROVED_ATTEMPT_SQL, [BATCH]);
  let processed = 0;
  for (const row of rows) {
    const claimed = await claimApprovedAttempt(row);
    if (!claimed) continue;

    const actionPayload = parseJsonRecord(row.action_payload);
    const request = handoffRequestFromActionPayload(actionPayload);
    try {
      if (!request) throw new Error('approved local harness checkpoint has invalid handoff metadata');
      const result = await runLocalHarnessAttempt(config, {
        taskId: row.task_id,
        title: row.title,
        request,
        actionPayload,
        resumePayload: row.resume_payload ? parseJsonRecord(row.resume_payload) : null,
      });
      await recordLocalHarnessCompletionEvent(row, request, result);
      processed += 1;
      console.log(`[worker] local harness ${config.kind} attempt ${request.requestId} -> task=${row.task_id} status=${result.status}`);
    } catch (err) {
      await recordLocalHarnessFailureEvent(row, request, err);
      captureException(err, { op: 'local_harness_attempt', checkpoint_id: row.checkpoint_id, task_id: row.task_id });
      console.error(`[worker] failed local harness attempt ${row.checkpoint_id}:`, String(err));
    }
  }
  return processed;
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
    discovery.memories.length > 0
      ? `User context:\n${discovery.memories.slice(0, 5).map((memory) => `- ${memory.content}`).join('\n')}`
      : null,
    results ? `Top results:\n${results}` : `Web: ${discovery.web.source}`,
    `Next actions:\n${actions}`,
  ];
  return parts.filter(Boolean).join('\n\n').slice(0, 2000);
}

async function processAgentHandoffRequests(): Promise<number> {
  const { rows } = await pool.query<HandoffRequestRow>(HANDOFF_REQUEST_SQL, [BATCH]);
  let processed = 0;
  for (const row of rows) {
    const request = parseAgentHandoffMetadata(row.metadata);
    if (!request) {
      await recordHandoffFailureEvent(row, null, 'invalid handoff metadata');
      continue;
    }
    try {
      const discovery = await discoverTaskContext(
        { id: row.task_id, ownerId: row.owner_id, title: row.title },
        { force: true, instructions: request.instructions, memories: await loadActiveMemories(pool, row.owner_id) }
      );
      if (!discovery) {
        await recordHandoffFailureEvent(row, request, 'handoff discovery returned no result');
        continue;
      }
      const brief = await runAgentResearch(row.title, request, discovery);
      await recordHandoffResearchProposal(row, request, discovery, brief);
      if (request.mode === 'attempt') {
        await recordAttemptApprovalGate(row, request, discovery, brief);
      }
      await recordHandoffCompletionEvent(row, request, discovery, brief);
      processed += 1;
      console.log(`[worker] handoff ${request.mode} ${request.requestId} -> task=${row.task_id}`);
    } catch (err) {
      await recordHandoffFailureEvent(row, request, err);
      captureException(err, { op: 'agent_handoff', request_id: request.requestId, task_id: row.task_id, mode: request.mode });
      console.error(`[worker] failed handoff ${request.requestId}:`, String(err));
    }
  }
  return processed;
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
  const started = performance.now();
  return startSpan('worker tick', 'worker.tick', async () => {
    let enriched = 0;
    let localHarnessAttempts = 0;
    let interviewResponses = 0;
    let handoffs = 0;
    let githubAssociations = 0;
    try {
      localHarnessAttempts = await processApprovedLocalHarnessAttempts();
      interviewResponses = await processApprovedInterviewResponses();
      handoffs = await processAgentHandoffRequests();
      githubAssociations = await processGitHubAssociations();
      const { rows } = await pool.query(SELECT_SQL, [BATCH]);
      if (rows.length === 0) {
        wideEvent('worker.tick', {
          duration_ms: Math.round(performance.now() - started),
          local_harness_attempts: localHarnessAttempts,
          interview_responses: interviewResponses,
          handoffs,
          github_associations: githubAssociations,
          enriched,
          batch_rows: 0,
        });
        return localHarnessAttempts + interviewResponses + handoffs + githubAssociations;
      }
  const ownerIds = [...new Set(rows.map((row) => row.owner_id as string))];
  const historyByOwner = new Map<string, CategoryHints>();
  const rulesByOwner = new Map<string, CategorisationRule[]>();
  const memoriesByOwner = new Map<string, Awaited<ReturnType<typeof loadActiveMemories>>>();
  if (ownerIds.length > 0) {
    const [history, rules, memoryPairs] = await Promise.all([
      pool.query(HISTORY_SQL, [ownerIds]),
      pool.query<CategorisationRuleRow>(CATEGORISATION_RULES_SQL, [ownerIds]),
      Promise.all(ownerIds.map(async (ownerId) => [ownerId, await loadActiveMemories(pool, ownerId)] as const)),
    ]);
    for (const [ownerId, memories] of memoryPairs) memoriesByOwner.set(ownerId, memories);
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
    for (const row of rules.rows) {
      const items = rulesByOwner.get(row.owner_id) ?? [];
      items.push({
        title: row.title,
        instructions: row.instructions,
        category: row.category,
        tags: decodeTags(row.tags),
      });
      rulesByOwner.set(row.owner_id, items);
    }
  }

  for (const row of rows) {
    try {
      const e = await enrich(
        row.title,
        new Date(),
        historyByOwner.get(row.owner_id) ?? {},
        rulesByOwner.get(row.owner_id) ?? []
      );
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
        const discovery = await discoverTaskContext(
          {
            id: row.id,
            ownerId: row.owner_id,
            title: row.title,
          },
          {
            force: true,
            instructions: 'Automatically research this newly captured item and identify the next useful action.',
            memories: memoriesByOwner.get(row.owner_id) ?? [],
          }
        );
        if (discovery) {
          await recordDiscoveryEvent(row.id, row.owner_id, discovery);
          await recordDiscoveryProposal(row.id, row.owner_id, discovery);
          const request = autoResearchRequest(row, 'Automatically research this newly captured item.');
          let brief: AgentResearchBrief | null = null;
          let researchError: unknown = null;
          try {
            brief = await runAgentResearch(row.title, request, discovery);
          } catch (err) {
            researchError = err;
          }
          if (needsInterview(discovery, brief, researchError)) {
            await recordInterviewPromptGate(
              row,
              discovery,
              researchError instanceof Error
                ? researchError.message
                : brief
                  ? `research confidence ${brief.confidence.toFixed(2)}`
                  : 'insufficient research context'
            );
          } else if (brief) {
            await recordAutoResearchProposal(row, request, discovery, brief);
            await recordAutoResearchCompletionEvent(row, request, discovery, brief);
          }
        }
        enriched += 1;
        console.log(
          `[worker] enriched ${row.id} -> category=${e.suggestedCategory ?? '∅'} ` +
            `due=${e.suggestedDueAt ?? '∅'} conf=${e.confidence.toFixed(2)} src=${e.source}`
        );
      }
    } catch (err) {
      captureException(err, { op: 'task_enrichment', task_id: row.id });
      console.error(`[worker] failed to enrich ${row.id}:`, String(err));
    }
  }
      wideEvent('worker.tick', {
        duration_ms: Math.round(performance.now() - started),
        local_harness_attempts: localHarnessAttempts,
        interview_responses: interviewResponses,
        handoffs,
        github_associations: githubAssociations,
        enriched,
        batch_rows: rows.length,
      });
      return enriched + localHarnessAttempts + interviewResponses + handoffs + githubAssociations;
    } catch (err) {
      captureException(err, { op: 'worker_tick', duration_ms: Math.round(performance.now() - started) });
      wideEvent('worker.tick', {
        duration_ms: Math.round(performance.now() - started),
        local_harness_attempts: localHarnessAttempts,
        interview_responses: interviewResponses,
        handoffs,
        github_associations: githubAssociations,
        enriched,
        error_type: err instanceof Error ? err.name : typeof err,
      });
      throw err;
    }
  });
}

async function main() {
  console.log(
    `[worker] capture enrichment worker up. poll=${POLL_MS}ms batch=${BATCH} ` +
      `llm=${process.env.OPENAI_API_KEY ? 'on' : 'off'} ` +
      `local_harness=${LOCAL_HARNESS_CONFIG ? `${LOCAL_HARNESS_CONFIG.kind}:${LOCAL_HARNESS_CONFIG.deviceName}` : 'off'} ` +
      `once=${RUN_ONCE}`
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
      captureException(err, { op: 'worker_loop' });
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
