import { createHash } from 'crypto';
import type pg from 'pg';

export type HitlRiskLevel = 'low' | 'medium' | 'high';

export interface AgentActionGate {
  ownerId: string;
  taskId?: string | null;
  threadId: string;
  checkpointKey?: string;
  interruptBefore: string;
  actionType: string;
  title: string;
  body?: string | null;
  payload: Record<string, unknown>;
  provenance?: Record<string, unknown>;
  confidence?: number | null;
  source?: string;
  riskLevel?: HitlRiskLevel;
}

export interface HumanGateResult {
  interrupted: boolean;
  riskLevel: HitlRiskLevel;
  checkpointId: string | null;
  proposalId: string | null;
  status: 'skipped' | 'waiting';
}

const LOW_RISK_ACTIONS = new Set([
  'task_enrichment',
  'task_context_lookup',
  'obsidian_search',
  'web_search',
  'calendar_read',
]);

const HIGH_RISK_ACTION_HINTS = [
  'send',
  'purchase',
  'buy',
  'book',
  'schedule',
  'delete',
  'cancel',
  'pay',
  'transfer',
  'write_file',
  'external_write',
];

export function deterministicUuid(input: string): string {
  const chars = createHash('sha256').update(input).digest('hex').slice(0, 32).split('');
  chars[12] = '5';
  chars[16] = ((Number.parseInt(chars[16], 16) & 0x3) | 0x8).toString(16);
  const h = chars.join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

export function classifyActionRisk(actionType: string): HitlRiskLevel {
  const normalized = actionType.trim().toLowerCase().replace(/[^a-z0-9]+/g, '_');
  if (LOW_RISK_ACTIONS.has(normalized) || normalized.startsWith('read_') || normalized.endsWith('_read')) {
    return 'low';
  }
  if (HIGH_RISK_ACTION_HINTS.some((hint) => normalized.includes(hint))) {
    return 'high';
  }
  return 'medium';
}

function boundedJSON(value: Record<string, unknown>, maxBytes: number): string {
  const encoded = JSON.stringify(value);
  return Buffer.byteLength(encoded, 'utf8') <= maxBytes ? encoded : JSON.stringify({ truncated: true });
}

function checkpointKeyFor(action: AgentActionGate): string {
  return (action.checkpointKey ?? `${action.interruptBefore}:${action.actionType}`)
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9:_-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 160);
}

export async function interruptForHumanDecision(
  client: pg.PoolClient,
  action: AgentActionGate
): Promise<HumanGateResult> {
  const riskLevel = action.riskLevel ?? classifyActionRisk(action.actionType);
  if (riskLevel === 'low') {
    return { interrupted: false, riskLevel, checkpointId: null, proposalId: null, status: 'skipped' };
  }

  const checkpointKey = checkpointKeyFor(action);
  const checkpointId = deterministicUuid(`${action.ownerId}:${action.threadId}:${checkpointKey}`);
  const proposalId = deterministicUuid(`${action.ownerId}:${action.threadId}:${checkpointKey}:proposal`);
  const source = (action.source ?? 'agent').slice(0, 80);
  const provenance = boundedJSON(
    {
      source,
      interrupt_before: action.interruptBefore,
      thread_id: action.threadId,
      checkpoint_key: checkpointKey,
      risk_level: riskLevel,
      ...(action.provenance ?? {}),
    },
    4096
  );
  const payload = boundedJSON(
    {
      ...action.payload,
      action_type: action.actionType,
      thread_id: action.threadId,
      checkpoint_key: checkpointKey,
      interrupt_before: action.interruptBefore,
      risk_level: riskLevel,
    },
    8192
  );

  await client.query(
    `INSERT INTO public.agent_proposals
       (id, owner_id, task_id, proposal_type, status, title, body, payload, provenance, confidence, source)
     VALUES ($1, $2, $3, 'action', 'pending', $4, $5, $6, $7, $8, $9)
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
      action.ownerId,
      action.taskId ?? null,
      action.title.slice(0, 160),
      action.body?.slice(0, 2000) ?? null,
      payload,
      provenance,
      action.confidence ?? null,
      source,
    ]
  );

  await client.query(
    `INSERT INTO public.agent_checkpoints
       (id, owner_id, task_id, proposal_id, thread_id, checkpoint_key, interrupt_before,
        action_type, risk_level, status, action_payload)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'waiting', $10)
     ON CONFLICT (id) DO UPDATE
       SET proposal_id = EXCLUDED.proposal_id,
           action_payload = EXCLUDED.action_payload,
           updated_at = now()
     WHERE public.agent_checkpoints.status = 'waiting'`,
    [
      checkpointId,
      action.ownerId,
      action.taskId ?? null,
      proposalId,
      action.threadId.slice(0, 160),
      checkpointKey,
      action.interruptBefore.slice(0, 160),
      action.actionType.slice(0, 80),
      riskLevel,
      payload,
    ]
  );

  return { interrupted: true, riskLevel, checkpointId, proposalId, status: 'waiting' };
}
