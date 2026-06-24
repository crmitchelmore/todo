import { config } from '../config';
import type { AgentProposalRecord } from '../powersync/schema';
import { getToken } from './auth';

export type ProposalDecision = 'accepted' | 'rejected';
export type ProposalResumePayload = Record<string, unknown>;

export interface ProposalMeta {
  actionType: string;
  riskLevel: string | null;
  reason: string | null;
  threadId: string | null;
  question: string | null;
  options: ProposalOption[];
  allowFreeText: boolean;
}

export interface ProposalOption {
  id: string;
  label: string;
  value: string;
}

interface ProposalDecisionResponse {
  ok?: boolean;
  error?: string;
}

function readRecord(value: unknown): Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value) ? value as Record<string, unknown> : {};
}

function parseJSONRecord(value: string | null | undefined): Record<string, unknown> {
  if (!value) return {};
  try {
    return readRecord(JSON.parse(value));
  } catch {
    return {};
  }
}

function readString(record: Record<string, unknown>, key: string): string | null {
  const value = record[key];
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function readOptions(value: unknown): ProposalOption[] {
  if (!Array.isArray(value)) return [];
  const out: ProposalOption[] = [];
  for (const item of value) {
    const record = readRecord(item);
    const id = readString(record, 'id');
    const label = readString(record, 'label');
    const optionValue = readString(record, 'value');
    if (!id || !label || !optionValue) continue;
    out.push({ id, label, value: optionValue });
  }
  return out.slice(0, 8);
}

export function proposalMeta(proposal: Pick<AgentProposalRecord, 'payload' | 'provenance' | 'proposal_type'>): ProposalMeta {
  const payload = parseJSONRecord(proposal.payload);
  const provenance = parseJSONRecord(proposal.provenance);
  return {
    actionType: readString(payload, 'action_type') ?? proposal.proposal_type ?? 'action',
    riskLevel: readString(payload, 'risk_level') ?? readString(provenance, 'risk_level'),
    reason: readString(payload, 'autonomy_reason') ?? readString(provenance, 'autonomy_reason'),
    threadId: readString(payload, 'thread_id') ?? readString(provenance, 'thread_id'),
    question: readString(payload, 'question'),
    options: readOptions(payload.options),
    allowFreeText: payload.allow_free_text === true,
  };
}

export async function decideAgentProposal(
  id: string,
  decision: ProposalDecision,
  resumePayload?: ProposalResumePayload
): Promise<void> {
  const token = getToken();
  if (!token) throw new Error('Not signed in.');
  const res = await fetch(`${config.backendUrl}/api/agent/proposals/${id}/decision`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      decision,
      resume_payload: resumePayload ?? {
        decided_by: 'web',
        decided_at: new Date().toISOString(),
      },
    }),
  });
  const body: ProposalDecisionResponse = await res.json().catch(() => ({}));
  if (!res.ok || !body.ok) throw new Error(body.error ?? `request failed (${res.status})`);
}
