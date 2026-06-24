import * as Sentry from '@sentry/react';

const dsn = import.meta.env.VITE_SENTRY_DSN as string | undefined;
const environment = (import.meta.env.VITE_SENTRY_ENVIRONMENT as string | undefined) ?? import.meta.env.MODE;
const release = (import.meta.env.VITE_APP_VERSION as string | undefined) ?? 'capture-web@dev';

export function initObservability(): void {
  if (!dsn?.trim()) return;
  Sentry.init({
    dsn,
    environment,
    release,
    integrations: [
      Sentry.browserTracingIntegration(),
      Sentry.replayIntegration({ maskAllText: true, blockAllMedia: true }),
    ],
    tracesSampleRate: Number(import.meta.env.VITE_SENTRY_TRACES_SAMPLE_RATE ?? 0.1),
    replaysSessionSampleRate: Number(import.meta.env.VITE_SENTRY_REPLAY_SAMPLE_RATE ?? 0),
    replaysOnErrorSampleRate: Number(import.meta.env.VITE_SENTRY_REPLAY_ON_ERROR_SAMPLE_RATE ?? 1),
  });
}

export function captureException(error: unknown, context: Record<string, unknown> = {}): void {
  if (!dsn?.trim()) return;
  Sentry.withScope((scope) => {
    for (const [key, value] of Object.entries(context)) scope.setExtra(key, redact(value));
    Sentry.captureException(error);
  });
}

export async function startSpan<T>(name: string, op: string, fn: () => Promise<T>): Promise<T> {
  if (!dsn?.trim()) return fn();
  return Sentry.startSpan({ name, op }, fn);
}

export function wideEvent(event: string, fields: Record<string, unknown>): void {
  const payload = {
    event,
    service: 'capture-web',
    release,
    environment,
    timestamp: new Date().toISOString(),
    ...(redact(fields) as Record<string, unknown>),
  };
  console.info(JSON.stringify(payload));
}

function redact(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(redact);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(Object.entries(value as Record<string, unknown>).map(([key, raw]) => [
    key,
    /token|secret|password|authorization|cookie|key/i.test(key) ? '[redacted]' : redact(raw),
  ]));
}
