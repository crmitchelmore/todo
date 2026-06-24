import { createHash } from 'node:crypto';
import * as Sentry from '@sentry/node';

const SERVICE_NAME = process.env.OTEL_SERVICE_NAME ?? 'capture-worker';
const SERVICE_VERSION = process.env.SERVICE_VERSION ?? process.env.RAILWAY_GIT_COMMIT_SHA ?? 'dev';
const ENVIRONMENT = process.env.SENTRY_ENVIRONMENT ?? process.env.RAILWAY_ENVIRONMENT_NAME ?? process.env.NODE_ENV ?? 'development';

export function initObservability(): void {
  const dsn = process.env.SENTRY_DSN?.trim();
  if (!dsn) return;
  Sentry.init({
    dsn,
    environment: ENVIRONMENT,
    release: `${SERVICE_NAME}@${SERVICE_VERSION}`,
    tracesSampleRate: Number(process.env.SENTRY_TRACES_SAMPLE_RATE ?? 0.1),
    enableLogs: true,
  });
}

export function captureException(error: unknown, context: Record<string, unknown> = {}): void {
  if (!process.env.SENTRY_DSN) return;
  Sentry.withScope((scope) => {
    for (const [key, value] of Object.entries(context)) {
      scope.setExtra(key, redact(value));
    }
    Sentry.captureException(error);
  });
}

export async function startSpan<T>(name: string, op: string, fn: () => Promise<T>): Promise<T> {
  if (!process.env.SENTRY_DSN) return fn();
  return Sentry.startSpan({ name, op }, fn);
}

export function wideEvent(event: string, fields: Record<string, unknown>): void {
  const payload = {
    event,
    service: SERVICE_NAME,
    service_version: SERVICE_VERSION,
    environment: ENVIRONMENT,
    timestamp: new Date().toISOString(),
    ...(redact(fields) as Record<string, unknown>),
  };
  console.log(JSON.stringify(payload));
}

export function ownerHash(ownerId: string): string {
  return createHash('sha256').update(ownerId).digest('hex').slice(0, 16);
}

function redact(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(redact);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(Object.entries(value as Record<string, unknown>).map(([key, raw]) => [
    key,
    /token|secret|password|authorization|cookie|key/i.test(key) ? '[redacted]' : redact(raw),
  ]));
}
