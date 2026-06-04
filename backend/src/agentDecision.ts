import type pg from 'pg';

export type AgentProposalDecision = 'accepted' | 'rejected';
export type AgentProposalDecisionOutcome = 'decided' | 'not_found' | 'not_pending';

export function parseAgentProposalDecision(value: unknown): AgentProposalDecision | null {
  return value === 'accepted' || value === 'rejected' ? value : null;
}

export function serializeResumePayload(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  let encoded: string;
  try {
    encoded = JSON.stringify(value);
  } catch {
    throw new Error('resume_payload must be JSON serialisable');
  }
  if (encoded === undefined) throw new Error('resume_payload must be JSON serialisable');
  if (Buffer.byteLength(encoded, 'utf8') > 4096) {
    throw new Error('resume_payload must be 4096 bytes or less');
  }
  return encoded;
}

export async function applyAgentProposalDecision(
  client: pg.PoolClient,
  ownerId: string,
  proposalId: string,
  decision: AgentProposalDecision,
  resumePayload: string | null
): Promise<AgentProposalDecisionOutcome> {
  const existing = await client.query(
    `SELECT id, status
       FROM public.agent_proposals
      WHERE owner_id = $1
        AND id = $2
      FOR UPDATE`,
    [ownerId, proposalId]
  );
  if ((existing.rowCount ?? 0) === 0) return 'not_found';
  if (existing.rows[0].status !== 'pending') return 'not_pending';

  const checkpointStatus = decision === 'accepted' ? 'approved' : 'rejected';
  await client.query(
    `UPDATE public.agent_proposals
        SET status = $3,
            decided_at = COALESCE(decided_at, now()),
            updated_at = now()
      WHERE owner_id = $1
        AND id = $2
        AND status = 'pending'`,
    [ownerId, proposalId, decision]
  );
  await client.query(
    `UPDATE public.agent_checkpoints
        SET status = $3,
            decided_at = COALESCE(decided_at, now()),
            resume_payload = CASE WHEN $4::text IS NULL THEN resume_payload ELSE $4 END,
            updated_at = now()
      WHERE owner_id = $1
        AND proposal_id = $2
        AND status = 'waiting'`,
    [ownerId, proposalId, checkpointStatus, resumePayload]
  );
  return 'decided';
}
