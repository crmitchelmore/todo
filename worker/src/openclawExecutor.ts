import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

import type { AgentHandoffRequest } from './handoff.js';

const execFileAsync = promisify(execFile);

export interface OpenClawExecutorEnv {
  readonly OPENCLAW_EXECUTOR_ENABLED?: string;
  readonly OPENCLAW_SSH_HOST?: string;
  readonly OPENCLAW_SSH_USER?: string;
  readonly OPENCLAW_SSH_PORT?: string;
  readonly OPENCLAW_SSH_KEY_PATH?: string;
  readonly OPENCLAW_WORKDIR?: string;
  readonly OPENCLAW_CLI?: string;
  readonly OPENCLAW_AGENT?: string;
  readonly OPENCLAW_TIMEOUT_SECONDS?: string;
  readonly OPENCLAW_THINKING?: string;
  readonly OPENCLAW_SSH_STRICT_HOST_KEY_CHECKING?: string;
  readonly OPENCLAW_SSH_CONNECT_TIMEOUT_SECONDS?: string;
}

export interface OpenClawConfig {
  enabled: boolean;
  host: string;
  user: string;
  port: number;
  keyPath: string;
  workdir: string;
  cli: string;
  agent: string;
  timeoutSeconds: number;
  thinking: 'medium' | 'high' | 'max' | null;
  strictHostKeyChecking: 'yes' | 'accept-new' | 'no';
  connectTimeoutSeconds: number;
}

export interface OpenClawAttemptInput {
  taskId: string;
  title: string;
  request: AgentHandoffRequest;
  actionPayload: Record<string, unknown>;
  resumePayload: Record<string, unknown> | null;
}

export interface OpenClawRunResult {
  runId: string | null;
  status: string;
  reply: string;
  raw: Record<string, unknown>;
  stdout: string;
}

interface CommandRunner {
  (
    file: string,
    args: readonly string[],
    options: { timeout: number; maxBuffer: number }
  ): Promise<{ stdout: string; stderr: string }>;
}

export function openClawConfigFromEnv(env: OpenClawExecutorEnv = process.env): OpenClawConfig | null {
  const enabled = env.OPENCLAW_EXECUTOR_ENABLED === '1' || env.OPENCLAW_EXECUTOR_ENABLED === 'true';
  const host = env.OPENCLAW_SSH_HOST?.trim() ?? '';
  const user = env.OPENCLAW_SSH_USER?.trim() ?? '';
  const keyPath = env.OPENCLAW_SSH_KEY_PATH?.trim() ?? '';
  if (!enabled || !host || !user || !keyPath) return null;

  const thinking = readThinking(env.OPENCLAW_THINKING);
  return {
    enabled,
    host,
    user,
    port: readPositiveInt(env.OPENCLAW_SSH_PORT, 22),
    keyPath,
    workdir: env.OPENCLAW_WORKDIR?.trim() || '/Users/bravostation/clawd',
    cli: env.OPENCLAW_CLI?.trim() || '/opt/homebrew/bin/openclaw',
    agent: env.OPENCLAW_AGENT?.trim() || 'imessage-agent',
    timeoutSeconds: readPositiveInt(env.OPENCLAW_TIMEOUT_SECONDS, 120),
    thinking,
    strictHostKeyChecking: readHostKeyChecking(env.OPENCLAW_SSH_STRICT_HOST_KEY_CHECKING),
    connectTimeoutSeconds: readPositiveInt(env.OPENCLAW_SSH_CONNECT_TIMEOUT_SECONDS, 10),
  };
}

export function buildOpenClawPrompt(input: OpenClawAttemptInput): string {
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
          const url = typeof item.url === 'string' ? ` — ${item.url}` : '';
          return `${index + 1}. ${title}${url}`;
        })
    : [];

  const parts = [
    'You are executing an approved Capture task handoff via OpenClaw.',
    'Respect the approved scope. Prefer reversible/read-only steps; if an action would spend money, message someone, delete data, or otherwise create consequential external state, stop and report the proposed action instead of doing it.',
    `Task: ${input.title}`,
    `Task ID: ${input.taskId}`,
    `Mode: ${input.request.mode}`,
    input.request.instructions ? `User instructions: ${input.request.instructions}` : null,
    nextActions.length > 0 ? `Suggested next actions:\n${nextActions.map((item) => `- ${item}`).join('\n')}` : null,
    results.length > 0 ? `Research context:\n${results.join('\n')}` : null,
    input.resumePayload ? `Approval resume payload:\n${JSON.stringify(input.resumePayload, null, 2)}` : null,
    'Return a concise summary of what you did, what evidence you found, and any remaining human decision required.',
  ].filter(Boolean);
  return parts.join('\n\n').slice(0, 6000);
}

export function buildOpenClawRemoteCommand(config: OpenClawConfig, message: string): string {
  const args = [
    config.cli,
    'agent',
    '--agent',
    config.agent,
    '--message',
    message,
    '--json',
    '--timeout',
    String(config.timeoutSeconds),
  ];
  if (config.thinking) args.push('--thinking', config.thinking);
  return `cd ${shellQuote(config.workdir)} && ${args.map(shellQuote).join(' ')}`;
}

export function buildOpenClawSshArgs(config: OpenClawConfig, remoteCommand: string): string[] {
  return [
    '-i',
    config.keyPath,
    '-p',
    String(config.port),
    '-o',
    'BatchMode=yes',
    '-o',
    `StrictHostKeyChecking=${config.strictHostKeyChecking}`,
    '-o',
    `ConnectTimeout=${config.connectTimeoutSeconds}`,
    `${config.user}@${config.host}`,
    remoteCommand,
  ];
}

export async function runOpenClawAttempt(
  config: OpenClawConfig,
  input: OpenClawAttemptInput,
  runner: CommandRunner = execFileAsync
): Promise<OpenClawRunResult> {
  const message = buildOpenClawPrompt(input);
  const remoteCommand = buildOpenClawRemoteCommand(config, message);
  let stdout: string;
  try {
    ({ stdout } = await runner('ssh', buildOpenClawSshArgs(config, remoteCommand), {
      timeout: (config.timeoutSeconds + config.connectTimeoutSeconds + 15) * 1000,
      maxBuffer: 256 * 1024,
    }));
  } catch (err) {
    throw new Error(safeExecutionError(err));
  }
  const trimmed = stdout.trim();
  const raw = parseOpenClawJSON(trimmed);
  const status = typeof raw.status === 'string' ? raw.status : 'unknown';
  const reply = typeof raw.reply === 'string' ? raw.reply : trimmed;
  const runId = typeof raw.runId === 'string' ? raw.runId : null;
  return { runId, status, reply: reply.slice(0, 4000), raw, stdout: trimmed.slice(0, 8000) };
}

function safeExecutionError(err: unknown): string {
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
  return `OpenClaw SSH command failed${details.length > 0 ? ` (${details.join('; ')})` : ''}`;
}

function parseOpenClawJSON(stdout: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(stdout) as unknown;
    return readRecord(parsed);
  } catch {
    return { status: 'unknown', reply: stdout };
  }
}

function shellQuote(value: string): string {
  return `'${value.replace(/'/g, `'\\''`)}'`;
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

function readThinking(value: string | undefined): OpenClawConfig['thinking'] {
  return value === 'medium' || value === 'high' || value === 'max' ? value : null;
}

function readHostKeyChecking(value: string | undefined): OpenClawConfig['strictHostKeyChecking'] {
  return value === 'yes' || value === 'no' || value === 'accept-new' ? value : 'accept-new';
}
