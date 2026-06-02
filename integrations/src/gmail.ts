import {
  CompletionSignal,
  Connector,
  ConnectorHealth,
  ConnectorName,
  ExtractedTodo,
  IntegrationNotConfiguredError,
  TaskForCompletionDetection,
} from "./types.js";

const GMAIL_ENV_VARS = ["GMAIL_IMAP_USER", "GMAIL_IMAP_APP_PASSWORD"] as const;

export const GMAIL_DEFAULT_HOST = "imap.gmail.com" as const;
export const GMAIL_DEFAULT_PORT = 993 as const;

type GmailEnv = Partial<Record<
  (typeof GMAIL_ENV_VARS)[number] | "GMAIL_IMAP_HOST" | "GMAIL_IMAP_PORT",
  string
>>;

export interface GmailConnectorConfig {
  readonly user?: string;
  readonly appPassword?: string;
  readonly host?: string;
  readonly port?: number;
  readonly transport?: GmailTransport;
}

/** Resolved IMAP credentials handed to a transport. */
export interface GmailImapConfig {
  readonly user: string;
  readonly appPassword: string;
  readonly host: string;
  readonly port: number;
}

export interface GmailTransport {
  extractTodos(config: GmailImapConfig, since: GmailSince): Promise<readonly ExtractedTodo[]>;
  detectCompletions(
    config: GmailImapConfig,
    tasks: readonly TaskForCompletionDetection[],
  ): Promise<readonly CompletionSignal[]>;
}

/** A lookback window expressed as a concrete cutoff date plus the raw spec for logging. */
export interface GmailSince {
  readonly spec: string;
  readonly cutoff: Date;
}

/**
 * Parse a lookback spec into a concrete cutoff date.
 * Accepts `"7d"`, `"36h"`, or an ISO-8601 date/datetime. Empty or invalid input throws.
 */
export function parseGmailSince(spec: string, now = new Date()): GmailSince {
  const trimmed = spec.trim();
  if (trimmed.length === 0) {
    throw new Error('Gmail `since` must be non-empty (e.g. "7d" or an ISO date).');
  }
  const rel = /^(\d+)([dh])$/.exec(trimmed);
  if (rel) {
    const amount = Number(rel[1]);
    const ms = rel[2] === "d" ? amount * 86_400_000 : amount * 3_600_000;
    return { spec: trimmed, cutoff: new Date(now.getTime() - ms) };
  }
  const asDate = new Date(trimmed);
  if (!Number.isNaN(asDate.getTime())) {
    return { spec: trimmed, cutoff: asDate };
  }
  throw new Error(`Gmail \`since\` not understood: ${spec}`);
}

class StubGmailTransport implements GmailTransport {
  async extractTodos(): Promise<readonly ExtractedTodo[]> {
    throw new Error(
      "Gmail IMAP transport is not available. Construct GmailConnector with an ImapGmailTransport.",
    );
  }

  async detectCompletions(): Promise<readonly CompletionSignal[]> {
    throw new Error(
      "Gmail IMAP transport is not available. Construct GmailConnector with an ImapGmailTransport.",
    );
  }
}

export class GmailConnector implements Connector {
  readonly name: ConnectorName = "gmail";

  private readonly user?: string;
  private readonly appPassword?: string;
  private readonly host: string;
  private readonly port: number;
  private readonly transport: GmailTransport;

  constructor(config: GmailConnectorConfig = {}) {
    this.user = nonEmpty(config.user ?? process.env.GMAIL_IMAP_USER);
    this.appPassword = nonEmpty(config.appPassword ?? process.env.GMAIL_IMAP_APP_PASSWORD);
    this.host = nonEmpty(config.host ?? process.env.GMAIL_IMAP_HOST) ?? GMAIL_DEFAULT_HOST;
    this.port = config.port ?? toPort(process.env.GMAIL_IMAP_PORT) ?? GMAIL_DEFAULT_PORT;
    this.transport = config.transport ?? new StubGmailTransport();
  }

  static fromEnv(env: GmailEnv = process.env): GmailConnector {
    return new GmailConnector({
      user: env.GMAIL_IMAP_USER,
      appPassword: env.GMAIL_IMAP_APP_PASSWORD,
      host: env.GMAIL_IMAP_HOST,
      port: toPort(env.GMAIL_IMAP_PORT),
    });
  }

  isConfigured(): boolean {
    return this.missingEnvVars().length === 0;
  }

  async healthCheck(): Promise<ConnectorHealth> {
    const missingEnvVars = this.missingEnvVars();
    if (missingEnvVars.length > 0) {
      return {
        name: this.name,
        configured: false,
        status: "not_configured",
        checkedAt: new Date().toISOString(),
        message: "Gmail IMAP credentials are not configured.",
        missingEnvVars,
      };
    }

    return {
      name: this.name,
      configured: true,
      status: "ok",
      checkedAt: new Date().toISOString(),
      message: `Gmail IMAP credentials present for ${this.user} (${this.host}:${this.port}).`,
    };
  }

  /**
   * Gmail IMAP setup notes (App Password + IMAP — no OAuth client to maintain):
   * - Enable 2-Step Verification, then create an App Password (Google Account -> Security ->
   *   App passwords) for "Mail". Ensure IMAP is enabled in Gmail settings.
   * - Set GMAIL_IMAP_USER (the address) and GMAIL_IMAP_APP_PASSWORD (the 16-char app password).
   * - Host/port default to imap.gmail.com:993 (implicit TLS); override via GMAIL_IMAP_HOST/PORT.
   * IMAP access is read-only in practice: we SEARCH + FETCH, never modify or delete.
   */
  async extractTodos(since: string): Promise<readonly ExtractedTodo[]> {
    const config = this.imapConfig();
    return this.transport.extractTodos(config, parseGmailSince(since));
  }

  async detectCompletions(
    tasks: readonly TaskForCompletionDetection[],
  ): Promise<readonly CompletionSignal[]> {
    const config = this.imapConfig();
    return this.transport.detectCompletions(config, tasks);
  }

  private imapConfig(): GmailImapConfig {
    const missingEnvVars = this.missingEnvVars();
    if (missingEnvVars.length > 0) {
      throw new IntegrationNotConfiguredError(this.name, missingEnvVars);
    }

    return {
      user: this.user as string,
      appPassword: this.appPassword as string,
      host: this.host,
      port: this.port,
    };
  }

  private missingEnvVars(): readonly string[] {
    const missing: string[] = [];
    if (!this.user) missing.push("GMAIL_IMAP_USER");
    if (!this.appPassword) missing.push("GMAIL_IMAP_APP_PASSWORD");
    return missing;
  }
}

function nonEmpty(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed && trimmed.length > 0 ? trimmed : undefined;
}

function toPort(value: string | undefined): number | undefined {
  const trimmed = value?.trim();
  if (!trimmed) return undefined;
  const n = Number(trimmed);
  return Number.isInteger(n) && n > 0 && n < 65_536 ? n : undefined;
}
