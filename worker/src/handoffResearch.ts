import { runCommand, type CommandRunner } from './commandRunner.js';
import type { TaskDiscovery } from './discovery.js';
import type { AgentHandoffRequest } from './handoff.js';

const DEFAULT_RESEARCH_MODEL = 'gpt-5.6-sol';

export interface AgentResearchBrief {
  source: 'llm';
  body: string;
  nextActions: string[];
  confidence: number;
  model: string;
}

export interface AgentResearchEnv {
  readonly OPENAI_API_KEY?: string;
  readonly OPENAI_BASE_URL?: string;
  readonly ENRICH_LLM_MODEL?: string;
  readonly HANDOFF_LLM_MODEL?: string;
  readonly RESEARCH_LLM_MODEL?: string;
  readonly RESEARCH_LLM_PROVIDER?: string;
  readonly CODEX_RESEARCH_COMMAND?: string;
  readonly CODEX_RESEARCH_WORKDIR?: string;
  readonly CODEX_RESEARCH_TIMEOUT_SECONDS?: string;
  readonly CODEX_RESEARCH_SANDBOX?: string;
}

export type FetchLike = (input: string | URL, init?: RequestInit) => Promise<Response>;
export type ExecLike = CommandRunner;

export async function runAgentResearch(
  taskTitle: string,
  request: AgentHandoffRequest,
  discovery: TaskDiscovery,
  options: {
    env?: AgentResearchEnv;
    fetchImpl?: FetchLike;
    execImpl?: ExecLike;
    now?: Date;
  } = {}
): Promise<AgentResearchBrief> {
  const env = options.env ?? process.env;
  const model = readResearchModel(env);
  if (readResearchProvider(env) === 'codex') {
    return runCodexResearch(taskTitle, request, discovery, model, env, options.now ?? new Date(), options.execImpl);
  }

  const apiKey = env.OPENAI_API_KEY?.trim();
  if (!apiKey) {
    throw new Error('LLM research is not configured: OPENAI_API_KEY is missing');
  }

  const baseUrl = (env.OPENAI_BASE_URL?.trim() || 'https://api.openai.com/v1').replace(/\/$/, '');
  const resp = await (options.fetchImpl ?? fetch)(`${baseUrl}/chat/completions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({
      model,
      temperature: 0.2,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: systemPrompt(options.now ?? new Date()) },
        { role: 'user', content: userPrompt(taskTitle, request, discovery) },
      ],
    }),
  });

  if (!resp.ok) {
    throw new Error(`LLM research failed: HTTP ${resp.status}`);
  }
  const json = await resp.json() as any;
  const content = json.choices?.[0]?.message?.content;
  if (typeof content !== 'string' || !content.trim()) {
    throw new Error('LLM research failed: empty response');
  }
  return parseResearchResponse(content, model);
}

async function runCodexResearch(
  taskTitle: string,
  request: AgentHandoffRequest,
  discovery: TaskDiscovery,
  model: string,
  env: AgentResearchEnv,
  now: Date,
  execImpl: ExecLike = runCommand
): Promise<AgentResearchBrief> {
  const command = env.CODEX_RESEARCH_COMMAND?.trim() || 'codex';
  const workdir = env.CODEX_RESEARCH_WORKDIR?.trim() || process.cwd();
  const sandbox = readCodexSandbox(env.CODEX_RESEARCH_SANDBOX);
  const timeoutSeconds = readPositiveInt(env.CODEX_RESEARCH_TIMEOUT_SECONDS, 180);
  const prompt = [
    systemPrompt(now),
    'Use the following task context. Return only the strict JSON object requested by the system prompt.',
    userPrompt(taskTitle, request, discovery),
  ].join('\n\n');

  const { stdout } = await execImpl(command, [
    'exec',
    '--json',
    '--sandbox',
    sandbox,
    '--model',
    model,
    '--cd',
    workdir,
    prompt,
  ], {
    cwd: workdir,
    timeout: timeoutSeconds * 1000,
    maxBuffer: 2 * 1024 * 1024,
  });
  const content = extractCodexAgentMessage(stdout);
  if (!content) {
    throw new Error('LLM research failed: Codex returned no agent message');
  }
  return parseResearchResponse(content, model);
}

function readResearchModel(env: AgentResearchEnv): string {
  return env.RESEARCH_LLM_MODEL?.trim()
    || env.HANDOFF_LLM_MODEL?.trim()
    || env.ENRICH_LLM_MODEL?.trim()
    || DEFAULT_RESEARCH_MODEL;
}

function readResearchProvider(env: AgentResearchEnv): 'api' | 'codex' {
  return env.RESEARCH_LLM_PROVIDER?.trim().toLowerCase() === 'codex' ? 'codex' : 'api';
}

function readCodexSandbox(value: string | undefined): 'read-only' | 'workspace-write' | 'danger-full-access' {
  const normalized = value?.trim();
  return normalized === 'workspace-write' || normalized === 'danger-full-access' ? normalized : 'read-only';
}

function readPositiveInt(value: string | undefined, fallback: number): number {
  const n = Number.parseInt(value ?? '', 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

function extractCodexAgentMessage(stdout: string): string | null {
  let lastError: string | null = null;
  const events = stdout
    .split(/\r?\n/)
    .map((line) => parseRecord(line.trim()))
    .filter((event): event is Record<string, unknown> => event !== null);
  for (let i = events.length - 1; i >= 0; i -= 1) {
    const item = readRecord(events[i].item);
    if (events[i].type === 'item.completed' && item.type === 'agent_message' && typeof item.text === 'string') {
      return item.text;
    }
    if (item.type === 'error' && typeof item.message === 'string') {
      lastError = item.message;
    }
  }
  if (lastError) throw new Error(`LLM research failed: ${lastError}`);
  return null;
}

function systemPrompt(now: Date): string {
  return [
    'You are Capture\'s task research agent.',
    'Do one thoughtful research/planning turn for a single todo item.',
    'Use the supplied user memories, prompt, and discovered web/search context.',
    'Do not claim you performed actions outside the provided context.',
    'Do not mutate external state or imply purchases/bookings/messages were sent.',
    'Return strict JSON with keys: summary, recommendations, next_actions, confidence.',
    'summary: a concise paragraph with useful reasoning.',
    'recommendations: array of 2-5 concrete recommendations or findings.',
    'next_actions: array of 1-5 safe next actions for the human or approval flow.',
    'confidence: number 0..1 based on evidence quality.',
    `Current time: ${now.toISOString()}.`,
  ].join(' ');
}

function userPrompt(taskTitle: string, request: AgentHandoffRequest, discovery: TaskDiscovery): string {
  return JSON.stringify({
    task: {
      title: taskTitle,
      handoff_mode: request.mode,
      instructions: request.instructions,
    },
    context: {
      query: discovery.query,
      location: discovery.location,
      memories: discovery.memories.slice(0, 8),
      web: discovery.web,
      deterministic_next_actions: discovery.nextActions,
    },
  });
}

export function parseResearchResponse(content: string, model = 'unknown'): AgentResearchBrief {
  let parsed: unknown;
  try {
    parsed = JSON.parse(content);
  } catch {
    throw new Error('LLM research failed: invalid JSON response');
  }
  if (!isRecord(parsed)) throw new Error('LLM research failed: response is not an object');

  const summary = stringValue(parsed.summary);
  if (!summary) throw new Error('LLM research failed: response missing summary');
  const recommendations = stringArray(parsed.recommendations).slice(0, 5);
  const nextActions = stringArray(parsed.next_actions).slice(0, 5);
  const confidence = clampConfidence(parsed.confidence);

  const lines = [
    summary,
    recommendations.length ? `Recommendations:\n${recommendations.map((item) => `- ${item}`).join('\n')}` : null,
    nextActions.length ? `Next actions:\n${nextActions.map((item) => `- ${item}`).join('\n')}` : null,
  ].filter(Boolean);

  return {
    source: 'llm',
    body: lines.join('\n\n').slice(0, 2000),
    nextActions,
    confidence,
    model,
  };
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.map(stringValue).filter((item): item is string => Boolean(item))
    : [];
}

function stringValue(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim().slice(0, 1000) : null;
}

function clampConfidence(value: unknown): number {
  const n = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(n)) return 0.5;
  return Math.max(0, Math.min(1, Number(n.toFixed(2))));
}

function parseRecord(value: string): Record<string, unknown> | null {
  if (!value) return null;
  try {
    const parsed = JSON.parse(value) as unknown;
    const record = readRecord(parsed);
    return Object.keys(record).length > 0 ? record : null;
  } catch {
    return null;
  }
}

function readRecord(value: unknown): Record<string, unknown> {
  return isRecord(value) ? value : {};
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
