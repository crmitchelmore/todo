export type ConnectorName = "obsidian" | "gmail";

export type ConnectorHealthStatus = "ok" | "not_configured" | "stubbed" | "error";

export interface ConnectorHealth {
  readonly name: ConnectorName;
  readonly configured: boolean;
  readonly status: ConnectorHealthStatus;
  readonly checkedAt: string;
  readonly message?: string;
  readonly missingEnvVars?: readonly string[];
}

export interface Connector {
  readonly name: ConnectorName;
  isConfigured(): boolean;
  healthCheck(): Promise<ConnectorHealth>;
}

export class IntegrationNotConfiguredError extends Error {
  readonly connector: ConnectorName;
  readonly missingEnvVars: readonly string[];

  constructor(connector: ConnectorName, missingEnvVars: readonly string[]) {
    const envList = missingEnvVars.join(", ");
    super(`${connector} integration is not configured. Set ${envList} before using it.`);
    this.name = "IntegrationNotConfiguredError";
    this.connector = connector;
    this.missingEnvVars = missingEnvVars;
  }
}

export interface VaultNote {
  readonly path: string;
  readonly content: string;
  readonly contentType: string;
  readonly retrievedAt: string;
}

export interface VaultSearchMatch {
  readonly context: string;
  readonly position?: {
    readonly start: number;
    readonly end: number;
  };
}

export interface VaultSearchHit {
  readonly path: string;
  readonly score: number;
  readonly excerpt?: string;
  readonly matches: readonly VaultSearchMatch[];
}

export interface EmailAddress {
  readonly name?: string;
  readonly address: string;
}

export interface ExtractedTodo {
  readonly source: "gmail";
  readonly sourceMessageId: string;
  readonly threadId?: string;
  readonly title: string;
  readonly sourceQuote: string;
  readonly confidence: number;
  readonly sender?: EmailAddress;
  readonly receivedAt?: string;
  readonly dueHint?: string;
  readonly labels: readonly string[];
}

export interface TaskForCompletionDetection {
  readonly id: string;
  readonly title: string;
  readonly context?: string;
  readonly createdAt?: string;
}

export interface CompletionSignal {
  readonly source: "gmail";
  readonly taskId: string;
  readonly messageId: string;
  readonly threadId?: string;
  readonly reason: string;
  readonly sourceQuote: string;
  readonly confidence: number;
  readonly receivedAt?: string;
}
