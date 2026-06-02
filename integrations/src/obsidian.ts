import {
  Connector,
  ConnectorHealth,
  ConnectorName,
  IntegrationNotConfiguredError,
  VaultNote,
  VaultSearchHit,
  VaultSearchMatch,
} from "./types.js";

const OBSIDIAN_ENV_VARS = ["OBSIDIAN_API_URL", "OBSIDIAN_API_KEY"] as const;

type ObsidianEnv = Partial<Record<(typeof OBSIDIAN_ENV_VARS)[number], string>>;

type Fetch = typeof fetch;

export interface ObsidianConnectorConfig {
  readonly apiUrl?: string;
  readonly apiKey?: string;
  readonly fetch?: Fetch;
}

export class ObsidianConnector implements Connector {
  readonly name: ConnectorName = "obsidian";

  private readonly apiUrl?: string;
  private readonly apiKey?: string;
  private readonly fetchImpl: Fetch;

  constructor(config: ObsidianConnectorConfig = {}) {
    this.apiUrl = normaliseBaseUrl(config.apiUrl ?? process.env.OBSIDIAN_API_URL);
    this.apiKey = nonEmpty(config.apiKey ?? process.env.OBSIDIAN_API_KEY);
    this.fetchImpl = config.fetch ?? fetch;
  }

  static fromEnv(env: ObsidianEnv = process.env): ObsidianConnector {
    return new ObsidianConnector({
      apiUrl: env.OBSIDIAN_API_URL,
      apiKey: env.OBSIDIAN_API_KEY,
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
        message: "Obsidian Local REST API credentials are not configured.",
        missingEnvVars,
      };
    }

    return {
      name: this.name,
      configured: true,
      status: "ok",
      checkedAt: new Date().toISOString(),
      message: "Obsidian credentials are present; live vault calls are only made when connector methods are invoked.",
    };
  }

  async searchVault(query: string): Promise<readonly VaultSearchHit[]> {
    const config = this.config();
    const trimmedQuery = query.trim();
    if (trimmedQuery.length === 0) {
      return [];
    }

    const response = await this.fetchImpl(`${config.apiUrl}/search/simple/?query=${encodeURIComponent(trimmedQuery)}`, {
      method: "POST",
      headers: authHeaders(config.apiKey, { Accept: "application/json" }),
    });

    await assertOk(response, "search Obsidian vault");
    const body = (await response.json()) as unknown;
    return parseSearchHits(body);
  }

  async getNote(path: string): Promise<VaultNote> {
    const config = this.config();
    const notePath = path.trim();
    if (notePath.length === 0) {
      throw new Error("Obsidian note path must be non-empty.");
    }

    const response = await this.fetchImpl(`${config.apiUrl}/vault/${encodeVaultPath(notePath)}`, {
      method: "GET",
      headers: authHeaders(config.apiKey, { Accept: "text/markdown, text/plain;q=0.9, */*;q=0.1" }),
    });

    await assertOk(response, "read Obsidian note");
    return {
      path: notePath,
      content: await response.text(),
      contentType: response.headers.get("content-type") ?? "text/markdown",
      retrievedAt: new Date().toISOString(),
    };
  }

  private config(): { apiUrl: string; apiKey: string } {
    const missingEnvVars = this.missingEnvVars();
    if (missingEnvVars.length > 0) {
      throw new IntegrationNotConfiguredError(this.name, missingEnvVars);
    }

    return { apiUrl: this.apiUrl as string, apiKey: this.apiKey as string };
  }

  private missingEnvVars(): readonly string[] {
    const missing: string[] = [];
    if (!this.apiUrl) missing.push("OBSIDIAN_API_URL");
    if (!this.apiKey) missing.push("OBSIDIAN_API_KEY");
    return missing;
  }
}

function authHeaders(apiKey: string, headers: Record<string, string> = {}): HeadersInit {
  return {
    ...headers,
    Authorization: `Bearer ${apiKey}`,
  };
}

function normaliseBaseUrl(value: string | undefined): string | undefined {
  const url = nonEmpty(value);
  return url?.replace(/\/+$/, "");
}

function nonEmpty(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed && trimmed.length > 0 ? trimmed : undefined;
}

function encodeVaultPath(path: string): string {
  return path.split("/").map(encodeURIComponent).join("/");
}

async function assertOk(response: Response, action: string): Promise<void> {
  if (response.ok) return;

  const body = await response.text().catch(() => "");
  const suffix = body.length > 0 ? `: ${body}` : "";
  throw new Error(`Failed to ${action}: HTTP ${response.status} ${response.statusText}${suffix}`);
}

function parseSearchHits(body: unknown): readonly VaultSearchHit[] {
  if (!Array.isArray(body)) {
    throw new Error("Unexpected Obsidian search response: expected an array.");
  }

  return body.map((item): VaultSearchHit => {
    const record = asRecord(item, "Obsidian search hit");
    const path = readString(record, "filename") ?? readString(record, "path");
    if (!path) {
      throw new Error("Unexpected Obsidian search response: hit missing filename/path.");
    }

    const matches = Array.isArray(record.matches) ? record.matches.map(parseSearchMatch) : [];
    return {
      path,
      score: readNumber(record, "score") ?? 0,
      excerpt: readString(record, "context") ?? matches[0]?.context,
      matches,
    };
  });
}

function parseSearchMatch(item: unknown): VaultSearchMatch {
  const record = asRecord(item, "Obsidian search match");
  const nestedMatch = isRecord(record.match) ? record.match : undefined;
  const start = nestedMatch ? readNumber(nestedMatch, "start") : readNumber(record, "start");
  const end = nestedMatch ? readNumber(nestedMatch, "end") : readNumber(record, "end");
  const context = readString(record, "context") ?? "";

  return start !== undefined && end !== undefined
    ? { context, position: { start, end } }
    : { context };
}

function asRecord(value: unknown, label: string): Record<string, unknown> {
  if (!isRecord(value)) {
    throw new Error(`Unexpected ${label}: expected an object.`);
  }
  return value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function readString(record: Record<string, unknown>, key: string): string | undefined {
  const value = record[key];
  return typeof value === "string" ? value : undefined;
}

function readNumber(record: Record<string, unknown>, key: string): number | undefined {
  const value = record[key];
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}
