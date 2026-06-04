import { useMemo, useState } from 'react';
import type { AgentProposalRecord, TaskRecord } from '../powersync/schema';
import { decideAgentProposal, proposalMeta, type ProposalDecision } from '../lib/proposals';

function label(value: string | null | undefined): string {
  return (value ?? 'action').replaceAll('_', ' ');
}

function confidence(proposal: AgentProposalRecord): string | null {
  return typeof proposal.confidence === 'number' ? `${Math.round(proposal.confidence * 100)}%` : null;
}

export function ApprovalQueue({
  proposals,
  tasksById,
}: {
  proposals: AgentProposalRecord[];
  tasksById: Map<string, TaskRecord>;
}) {
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const pending = useMemo(() => proposals.filter((p) => p.proposal_type === 'action'), [proposals]);
  if (pending.length === 0) return null;

  async function decide(proposal: AgentProposalRecord, decision: ProposalDecision): Promise<void> {
    setBusyId(proposal.id);
    setError(null);
    try {
      await decideAgentProposal(proposal.id, decision);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusyId(null);
    }
  }

  return (
    <section className="approval-queue" aria-label="Consequential action approvals">
      <div className="approval-head">
        <div>
          <h2>Approval queue · {pending.length}</h2>
          <p>Consequential agent work pauses here until you explicitly approve or reject it.</p>
        </div>
        <span className="approval-seal">HITL</span>
      </div>
      {error && <p className="approval-error">{error}</p>}
      <div className="approval-stack">
        {pending.map((proposal) => {
          const meta = proposalMeta(proposal);
          const task = proposal.task_id ? tasksById.get(proposal.task_id) : null;
          const busy = busyId === proposal.id;
          return (
            <article key={proposal.id} className={`approval-card risk-${meta.riskLevel ?? 'medium'}`}>
              <div className="approval-card-top">
                <span className="approval-action">{label(meta.actionType)}</span>
                <span className="approval-risk">{meta.riskLevel ?? 'review'}</span>
                {confidence(proposal) && <span className="approval-confidence">{confidence(proposal)}</span>}
              </div>
              <h3>{proposal.title}</h3>
              <p>{proposal.body || 'Review the proposed action before the agent continues.'}</p>
              {task && <p className="approval-context">Task: {task.title}</p>}
              <dl className="approval-meta">
                {meta.reason && (
                  <>
                    <dt>Why paused</dt>
                    <dd>{meta.reason}</dd>
                  </>
                )}
                {meta.threadId && (
                  <>
                    <dt>Thread</dt>
                    <dd>{meta.threadId}</dd>
                  </>
                )}
              </dl>
              <div className="approval-actions">
                <button className="primary approval-primary" disabled={busy} onClick={() => void decide(proposal, 'accepted')}>
                  {busy ? 'Working…' : 'Approve'}
                </button>
                <button className="ghost" disabled={busy} onClick={() => void decide(proposal, 'rejected')}>
                  Reject
                </button>
              </div>
            </article>
          );
        })}
      </div>
    </section>
  );
}
