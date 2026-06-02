import {
  CompletionSignal,
  Connector,
  ConnectorHealth,
  ConnectorName,
  ExtractedTodo,
  IntegrationNotConfiguredError,
  TaskForCompletionDetection,
} from "./types.js";

const GMAIL_ENV_VARS = ["GMAIL_CLIENT_ID", "GMAIL_CLIENT_SECRET", "GMAIL_REFRESH_TOKEN"] as const;

export const GMAIL_READONLY_SCOPE = "https://www.googleapis.com/auth/gmail.readonly" as const;

type GmailEnv = Partial<Record<(typeof GMAIL_ENV_VARS)[number], string>>;

export interface GmailConnectorConfig {
  readonly clientId?: string;
  readonly clientSecret?: string;
  readonly refreshToken?: string;
  readonly transport?: GmailTransport;
}

export interface GmailOAuthConfig {
  readonly clientId: string;
  readonly clientSecret: string;
  readonly refreshToken: string;
  readonly scopes: readonly [typeof GMAIL_READONLY_SCOPE];
}

export interface GmailTransport {
  extractTodos(config: GmailOAuthConfig, sinceQuery: string): Promise<readonly ExtractedTodo[]>;
  detectCompletions(
    config: GmailOAuthConfig,
    tasks: readonly TaskForCompletionDetection[],
  ): Promise<readonly CompletionSignal[]>;
}

class StubGmailTransport implements GmailTransport {
  async extractTodos(): Promise<readonly ExtractedTodo[]> {
    throw new Error("Gmail transport is not wired yet. Plug in an OAuth2 Gmail API client at GmailTransport.");
  }

  async detectCompletions(): Promise<readonly CompletionSignal[]> {
    throw new Error("Gmail transport is not wired yet. Plug in an OAuth2 Gmail API client at GmailTransport.");
  }
}

export class GmailConnector implements Connector {
  readonly name: ConnectorName = "gmail";

  private readonly clientId?: string;
  private readonly clientSecret?: string;
  private readonly refreshToken?: string;
  private readonly transport: GmailTransport;

  constructor(config: GmailConnectorConfig = {}) {
    this.clientId = nonEmpty(config.clientId ?? process.env.GMAIL_CLIENT_ID);
    this.clientSecret = nonEmpty(config.clientSecret ?? process.env.GMAIL_CLIENT_SECRET);
    this.refreshToken = nonEmpty(config.refreshToken ?? process.env.GMAIL_REFRESH_TOKEN);
    this.transport = config.transport ?? new StubGmailTransport();
  }

  static fromEnv(env: GmailEnv = process.env): GmailConnector {
    return new GmailConnector({
      clientId: env.GMAIL_CLIENT_ID,
      clientSecret: env.GMAIL_CLIENT_SECRET,
      refreshToken: env.GMAIL_REFRESH_TOKEN,
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
        message: "Gmail OAuth2 credentials are not configured.",
        missingEnvVars,
      };
    }

    return {
      name: this.name,
      configured: true,
      status: "stubbed",
      checkedAt: new Date().toISOString(),
      message: "Gmail OAuth2 credentials are present; API transport is intentionally stubbed until wiring work.",
    };
  }

  /**
   * Gmail API setup notes:
   * - Required OAuth2 scope: https://www.googleapis.com/auth/gmail.readonly
   * - Token flow: create an OAuth client in Google Cloud, send the owner through the consent flow
   *   with the readonly scope, exchange the one-time code for access/refresh tokens, then store only
   *   the refresh token in GMAIL_REFRESH_TOKEN. The future transport should exchange it for short-lived
   *   access tokens before calling users.messages.list/get.
   * - This boundary intentionally avoids a googleapis runtime dependency; plug the real client into
   *   GmailTransport when the integration is ready to run.
   */
  async extractTodos(sinceQuery: string): Promise<readonly ExtractedTodo[]> {
    const config = this.oauthConfig();
    const query = sinceQuery.trim();
    if (query.length === 0) {
      throw new Error("Gmail sinceQuery must be non-empty.");
    }

    return this.transport.extractTodos(config, query);
  }

  async detectCompletions(
    tasks: readonly TaskForCompletionDetection[],
  ): Promise<readonly CompletionSignal[]> {
    const config = this.oauthConfig();
    return this.transport.detectCompletions(config, tasks);
  }

  private oauthConfig(): GmailOAuthConfig {
    const missingEnvVars = this.missingEnvVars();
    if (missingEnvVars.length > 0) {
      throw new IntegrationNotConfiguredError(this.name, missingEnvVars);
    }

    return {
      clientId: this.clientId as string,
      clientSecret: this.clientSecret as string,
      refreshToken: this.refreshToken as string,
      scopes: [GMAIL_READONLY_SCOPE],
    };
  }

  private missingEnvVars(): readonly string[] {
    const missing: string[] = [];
    if (!this.clientId) missing.push("GMAIL_CLIENT_ID");
    if (!this.clientSecret) missing.push("GMAIL_CLIENT_SECRET");
    if (!this.refreshToken) missing.push("GMAIL_REFRESH_TOKEN");
    return missing;
  }
}

function nonEmpty(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed && trimmed.length > 0 ? trimmed : undefined;
}
