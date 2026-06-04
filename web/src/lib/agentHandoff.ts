import { config } from '../config';
import { getToken } from './auth';

export type AgentHandoffMode = 'research' | 'attempt';

interface AgentHandoffResponse {
  ok?: boolean;
  request_id?: string;
  error?: string;
}

export async function requestAgentHandoff(
  taskId: string,
  mode: AgentHandoffMode,
  instructions: string | null
): Promise<string> {
  const token = getToken();
  if (!token) throw new Error('Not signed in.');
  const res = await fetch(`${config.backendUrl}/api/tasks/${taskId}/agent-handoff`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ mode, instructions }),
  });
  const body: AgentHandoffResponse = await res.json().catch(() => ({}));
  if (!res.ok || !body.ok || !body.request_id) {
    throw new Error(body.error ?? `request failed (${res.status})`);
  }
  return body.request_id;
}
