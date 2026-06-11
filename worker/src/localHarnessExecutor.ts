import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

import type { AgentHandoffRequest } from './handoff.js';

const execFileAsync = promisify(execFile);

export type LocalHarnessKind = 'copilot-cli' | 'hermes' | 'openclaw' | 'custom';

export interface LocalHarnessEnv {
  readonly LOCAL_HARNESS_ENABLED?: string;
  readonly LOCAL_HARNESS_KIND?: string;
  readonly LOCAL_HARNESS_COMMAND?: string;
  readonly LOCAL_HARNESS_WORKDIR?: string;
  readonly LOCAL_HARNESS_TIMEOUT_SECONDS?: string;
  readonly LOCAL_HARNESS_ARGS_JSON?: string;
  readonly LOCAL_HARNESS_AGENT?: string;
  readonly LOCAL_HARNESS_THINKING?: string;
  readonly LOCAL_HARNESS_DEVICE_ID?: string;
  readonly LOCAL_HARNESS_DEVICE_NAME?: string;
}

export interface LocalHarnessConfig {
  enabled: boolean;
  kind: LocalHarnessKind;
  command: string;
  argsTemplate: string[];
  workdir: string;
  timeoutSeconds: number;
  deviceId: string;
  deviceName: string;
}

export interface LocalHarnessAttemptInput {
  taskId: string;
  title: string;
  request: AgentHandoffRequest;
  actionPayload: Record<string, unknown>;
  resumePayload: Record<string, unknown> | null;
}

export interface LocalHarnessRunResult {
  runId: string | null;
  status: string;
  reply: string;
  raw: Record<string, unknown>;
  stdout: string;
  harnessKind: LocalHarnessKind;
  deviceId: string;
  deviceName: string;
}

interface CommandRunner {
  (
    file: string,
    args: readonly string[],
    options: { cwd: string; timeout: number; maxBuffer: number }
  ): Promise<{ stdout: string; stderr: string }>;
}

export function localHarnessConfigFromEnv(env: LocalHarnessEnv = process.env): LocalHarnessConfig | null {
  const enabled = env.LOCAL_HARNESS_ENABLED === '1' || env.LOCAL_HARNESS_ENABLED === 'true';
  if (!enabled) return null;

  const kind = readHarnessKind(env.LOCAL_HARNESS_KIND);
  const command = env.LOCAL_HARNESS_COMMAND?.trim() || defaultCommand(kind);
  if (!command) return null;

  const argsTemplate = readArgsTemplate(env, kind);
  return {
    enabled,
    kind,
    command,
    argsTemplate,
    workdir: env.LOCAL_HARNESS_WORKDIR?.trim() || process.cwd(),
    timeoutSeconds: readPositiveInt(env.LOCAL_HARNESS_TIMEOUT_SECONDS, 120),
    deviceId: env.LOCAL_HARNESS_DEVICE_ID?.trim() || 'local-device',
    deviceName: env.LOCAL_HARNESS_DEVICE_NAME?.trim() || 'Local harness',
  };
}

export function buildHarnessPrompt(input: LocalHarnessAttemptInput): string {
  const discovery = readRecord(input.actionPayload.discovery);
  const nextActions = Array.isArray(discovery.nextActions)
    ? discovery.nextActions.filter((item): item is string => typeof item === 'string').slice(0, 8)
    : [];
  const web = readRecord(discovery.web);
  const results = Array.isArray(web.results)
    ? web.results
      .filter((item): item is Record<string, unknown> => typeof item === 'object' && item !== null && !Array.isArray(item))
      .slice(0, 5)
      .map((item, index) => {
        const title = typeof item.title === 'string' ? item.title : 'Untitled result';
        const url = typeof item.url === 'string' ? ` - ${item.url}` : '';
        return `${index + 1}. ${title}${url}`;
      })
    : [];

  const parts = [
    'You are executing an approved Capture task handoff on this local computer.',
    'Respect the approved scope. Prefer reversible/read-only steps. If an action would spend money, message someone, delete data, or otherwise create consequential external state, stop and report the proposed action instead of doing it.',
    `Task: ${input.title}`,
    `Task ID: ${input.taskId}`,
    `Mode: ${input.request.mode}`,
    input.request.instructions ? `User instructions: ${input.request.instructions}` : null,
    nextActions.length > 0 ? `Suggested next actions:\n${nextActions.map((item) => `- ${item}`).join('\n')}` : null,
    results.length > 0 ? `Research context:\n${results.join('\n')}` : null,
    input.resumePayload ? `Approval resume payload:\n${JSON.stringify(input.resumePayload, null, 2)}` : null,
    'Return JSON if the harness supports it. Include a concise summary of what you did, evidence found, and any remaining human decision required.',
  ].filter(Boolean);
  return parts.join('\n\n').slice(0, 6000);
}

export function buildLocalHarnessArgs(config: LocalHarnessConfig, prompt: string): string[] {
  return config.argsTemplate.map((arg) =>
    arg
      .replaceAll('{prompt}', prompt)
      .replaceAll('{timeout}', String(config.timeoutSeconds))
      .replaceAll('{deviceId}', config.deviceId)
      .replaceAll('{deviceName}', config.deviceName)
  );
}

export async function runLocalHarnessAttempt(
  config: LocalHarnessConfig,
  input: LocalHarnessAttemptInput,
  runner: CommandRunner = execFileAsync
): Promise<LocalHarnessRunResult> {
  const prompt = buildHarnessPrompt(input);
  const args = buildLocalHarnessArgs(config, prompt);
  let stdout: string;
  try {
    ({ stdout } = await runner(config.command, args, {
      cwd: config.workdir,
      timeout: (config.timeoutSeconds + 15) * 1000,
      maxBuffer: 256 * 1024,
    }));
  } catch (err) {
    throw new Error(safeExecutionError(config, err));
  }
  const trimmed = stdout.trim();
  const raw = parseHarnessJSON(trimmed);
  const status = typeof raw.status === 'string' ? raw.status : 'unknown';
  const reply = extractHarnessReply(raw) ?? trimmed;
  const runId = typeof raw.runId === 'string' ? raw.runId : typeof raw.run_id === 'string' ? raw.run_id : null;
  return {
    runId,
    status,
    reply: reply.slice(0, 4000),
    raw,
    stdout: trimmed.slice(0, 8000),
    harnessKind: config.kind,
    deviceId: config.deviceId,
    deviceName: config.deviceName,
  };
}

function readHarnessKind(value: string | undefined): LocalHarnessKind {
  const normalized = value?.trim().toLowerCase();
  return normalized === 'copilot-cli' || normalized === 'hermes' || normalized === 'openclaw' || normalized === 'custom'
    ? normalized
    : 'custom';
}

function defaultCommand(kind: LocalHarnessKind): string {
  switch (kind) {
    case 'copilot-cli':
      return 'copilot';
    case 'hermes':
      return 'hermes';
    case 'openclaw':
      return 'openclaw';
    case 'custom':
      return '';
  }
}

function readArgsTemplate(env: LocalHarnessEnv, kind: LocalHarnessKind): string[] {
  const custom = env.LOCAL_HARNESS_ARGS_JSON?.trim();
  if (custom) {
    const parsed = parseHarnessJSON(custom);
    if (Array.isArray(parsed.args)) return parsed.args.filter((arg): arg is string => typeof arg === 'string');
  }

  switch (kind) {
    case 'openclaw': {
      const args = ['agent', '--message', '{prompt}', '--json', '--timeout', '{timeout}'];
      const agent = env.LOCAL_HARNESS_AGENT?.trim();
      if (agent) args.splice(1, 0, '--agent', agent);
      const thinking = readThinking(env.LOCAL_HARNESS_THINKING);
      if (thinking) args.push('--thinking', thinking);
      return args;
    }
    case 'hermes':
      return ['run', '{prompt}', '--output', 'json'];
    case 'copilot-cli':
      return ['-p', '{prompt}', '--json'];
    case 'custom':
      return ['{prompt}'];
  }
}

function safeExecutionError(config: LocalHarnessConfig, err: unknown): string {
  const error = err as { code?: unknown; signal?: unknown; killed?: unknown; stderr?: unknown; stdout?: unknown };
  const details = [
    error.killed === true ? 'timeout' : null,
    error.signal ? `signal=${String(error.signal)}` : null,
    error.code !== undefined ? `exit=${String(error.code)}` : null,
    typeof error.stderr === 'string' && error.stderr.trim()
      ? `stderr=${error.stderr.trim().slice(0, 1000)}`
      : null,
    typeof error.stdout === 'string' && error.stdout.trim()
      ? `stdout=${error.stdout.trim().slice(0, 1000)}`
      : null,
  ].filter(Boolean);
  return `Local harness ${config.kind} command failed${details.length > 0 ? ` (${details.join('; ')})` : ''}`;
}

function parseHarnessJSON(stdout: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(stdout) as unknown;
    return readRecord(parsed);
  } catch {
    return { status: 'unknown', reply: stdout };
  }
}

function extractHarnessReply(raw: Record<string, unknown>): string | null {
  if (typeof raw.reply === 'string') return raw.reply;
  if (typeof raw.summary === 'string') return raw.summary;
  if (typeof raw.output === 'string') return raw.output;
  const result = readRecord(raw.result);
  if (typeof result.reply === 'string') return result.reply;
  if (typeof result.summary === 'string') return result.summary;
  const payloads = result.payloads;
  if (Array.isArray(payloads)) {
    const texts = payloads
      .map((payload) => readRecord(payload).text)
      .filter((text): text is string => typeof text === 'string' && text.trim().length > 0);
    if (texts.length > 0) return texts.join('\n\n');
  }
  return null;
}

function readRecord(value: unknown): Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function readPositiveInt(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function readThinking(value: string | undefined): string | null {
  return value === 'medium' || value === 'high' || value === 'max' ? value : null;
}
