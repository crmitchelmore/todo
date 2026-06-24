import { config } from '../config';
import { getToken } from './auth';
import { captureException, startSpan, wideEvent } from '../observability';

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
  return startSpan('Request agent handoff', 'ui.action', async () => {
    const started = performance.now();
    const token = getToken();
    if (!token) throw new Error('Not signed in.');
    try {
      const res = await fetch(`${config.backendUrl}/api/tasks/${taskId}/agent-handoff`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({ mode, instructions }),
      });
      const body: AgentHandoffResponse = await res.json().catch(() => ({}));
      if (!res.ok || !body.ok || !body.request_id) {
        throw new Error(body.error ?? `request failed (${res.status})`);
      }
      wideEvent('web.agent_handoff', {
        task_id: taskId,
        mode,
        duration_ms: Math.round(performance.now() - started),
        status: 'ok',
      });
      return body.request_id;
    } catch (error) {
      captureException(error, { op: 'web_agent_handoff', task_id: taskId, mode });
      wideEvent('web.agent_handoff', {
        task_id: taskId,
        mode,
        duration_ms: Math.round(performance.now() - started),
        status: 'error',
        error_type: error instanceof Error ? error.name : typeof error,
      });
      throw error;
    }
  });
}
