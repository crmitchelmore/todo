export type AgentHandoffMode = 'research' | 'attempt';

export interface AgentHandoffRequest {
  requestId: string;
  mode: AgentHandoffMode;
  instructions: string | null;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function parseAgentHandoffMetadata(metadata: unknown): AgentHandoffRequest | null {
  const record = typeof metadata === 'string' ? parseJSON(metadata) : readRecord(metadata);
  const requestId = typeof record.request_id === 'string' && UUID_RE.test(record.request_id)
    ? record.request_id
    : null;
  const mode = record.mode === 'research' || record.mode === 'attempt' ? record.mode : null;
  const instructions = typeof record.instructions === 'string' && record.instructions.trim()
    ? record.instructions.trim().slice(0, 1000)
    : null;
  if (!requestId || !mode) return null;
  return { requestId, mode, instructions };
}

function parseJSON(value: string): Record<string, unknown> {
  try {
    return readRecord(JSON.parse(value));
  } catch {
    return {};
  }
}

function readRecord(value: unknown): Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}
