import { createHash } from 'crypto';

export type AgentHandoffMode = 'research' | 'attempt';

export interface AgentHandoffInput {
  mode: AgentHandoffMode;
  instructions: string | null;
}

export const AGENT_HANDOFF_INSTRUCTIONS_MAX = 1000;
const MODE_SET = new Set<AgentHandoffMode>(['research', 'attempt']);

export function parseAgentHandoffInput(body: unknown): AgentHandoffInput | null {
  const record = isRecord(body) ? body : {};
  const mode = typeof record.mode === 'string' && MODE_SET.has(record.mode as AgentHandoffMode)
    ? record.mode as AgentHandoffMode
    : null;
  if (!mode) return null;
  const instructions = typeof record.instructions === 'string'
    ? record.instructions.trim().slice(0, AGENT_HANDOFF_INSTRUCTIONS_MAX) || null
    : null;
  return { mode, instructions };
}

export function agentHandoffRequestId(params: {
  ownerId: string;
  taskId: string;
  mode: AgentHandoffMode;
  instructions: string | null;
  now?: Date;
}): string {
  const bucket = Math.floor((params.now?.getTime() ?? Date.now()) / 30_000);
  return deterministicUuid([
    params.ownerId,
    params.taskId,
    params.mode,
    params.instructions ?? '',
    bucket,
  ].join(':'));
}

function deterministicUuid(input: string): string {
  const chars = createHash('sha256').update(input).digest('hex').slice(0, 32).split('');
  chars[12] = '5';
  chars[16] = ((Number.parseInt(chars[16], 16) & 0x3) | 0x8).toString(16);
  const h = chars.join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
