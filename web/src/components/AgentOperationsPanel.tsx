import type { AgentProposalRecord } from '../powersync/schema';

function countByType(proposals: AgentProposalRecord[], type: string): number {
  return proposals.filter((p) => p.proposal_type === type).length;
}

export function AgentOperationsPanel({
  captureCount,
  actionProposals,
  researchProposals,
  connected,
}: {
  captureCount: number;
  actionProposals: AgentProposalRecord[];
  researchProposals: AgentProposalRecord[];
  connected: boolean;
}) {
  const researchCount = researchProposals.length;
  const attemptCount = actionProposals.filter((p) => p.source === 'agent-handoff').length;
  return (
    <section className="agent-ops" aria-label="AI operations loop">
      <div className="agent-ops-orbit" aria-hidden="true">
        <span />
        <span />
        <span />
      </div>
      <div className="agent-ops-copy">
        <span className="agent-ops-kicker">AI operations loop</span>
        <h2>Capture → research → approve → history</h2>
        <p>
          Low-risk discovery runs in the background. Any attempt to mutate the outside world pauses
          here for explicit approval before the agent continues.
        </p>
      </div>
      <div className="agent-ops-metrics">
        <Metric label="confirm" value={captureCount} tone={captureCount > 0 ? 'signal' : 'quiet'} />
        <Metric label="research" value={researchCount} tone={researchCount > 0 ? 'iris' : 'quiet'} />
        <Metric label="approve" value={actionProposals.length} tone={actionProposals.length > 0 ? 'danger' : 'quiet'} />
        <Metric label="attempts" value={attemptCount} tone={attemptCount > 0 ? 'signal' : 'quiet'} />
        <Metric label="sync" value={connected ? 'live' : 'off'} tone={connected ? 'mint' : 'quiet'} />
      </div>
      {researchCount > 0 && (
        <p className="agent-ops-subline">
          {countByType(researchProposals, 'task_update')} research brief{researchCount === 1 ? '' : 's'} waiting in task detail.
        </p>
      )}
    </section>
  );
}

function Metric({
  label,
  value,
  tone,
}: {
  label: string;
  value: number | string;
  tone: 'signal' | 'mint' | 'iris' | 'danger' | 'quiet';
}) {
  return (
    <div className={`agent-ops-metric tone-${tone}`}>
      <strong>{value}</strong>
      <span>{label}</span>
    </div>
  );
}
