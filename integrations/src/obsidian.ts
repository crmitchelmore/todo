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
const DEFAULT_REQUEST_TIMEOUT_MS = 8_000;

type ObsidianEnv = Partial<Record<(typeof OBSIDIAN_ENV_VARS)[number], string>>;

type Fetch = typeof fetch;

export interface ObsidianConnectorConfig {
  readonly apiUrl?: string;
  readonly apiKey?: string;
  readonly fetch?: Fetch;
  readonly requestTimeoutMs?: number;
}

export interface ObsidianTaskWrite {
  readonly title: string;
  readonly dueAt?: Date | string | null;
  readonly completedAt?: Date | string | null;
  readonly tags?: readonly string[];
  readonly priority?: number | null;
}

export interface DailyNoteWriteOptions {
  readonly date?: Date;
  readonly path?: string;
  readonly pathPattern?: string;
  readonly sectionHeading?: string;
}

export interface DailyNoteWriteResult {
  readonly path: string;
  readonly lines: readonly string[];
  readonly writtenAt: string;
}

export class ObsidianConnector implements Connector {
  readonly name: ConnectorName = "obsidian";

  private readonly apiUrl?: string;
  private readonly apiKey?: string;
  private readonly fetchImpl: Fetch;
  private readonly requestTimeoutMs: number;

  constructor(config: ObsidianConnectorConfig = {}) {
    this.apiUrl = normaliseBaseUrl(config.apiUrl ?? process.env.OBSIDIAN_API_URL);
    this.apiKey = nonEmpty(config.apiKey ?? process.env.OBSIDIAN_API_KEY);
    this.fetchImpl = config.fetch ?? fetch;
    this.requestTimeoutMs = config.requestTimeoutMs ?? DEFAULT_REQUEST_TIMEOUT_MS;
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

    const config = this.config();
    try {
      const response = await this.fetchWithTimeout(`${config.apiUrl}/`, {
        method: "GET",
        headers: authHeaders(config.apiKey, { Accept: "application/json" }),
      });
      if (!response.ok) {
        return {
          name: this.name,
          configured: true,
          status: "error",
          checkedAt: new Date().toISOString(),
          message: `Obsidian Local REST API health probe failed with HTTP ${response.status}.`,
        };
      }
      return {
        name: this.name,
        configured: true,
        status: "ok",
        checkedAt: new Date().toISOString(),
        message: "Obsidian Local REST API is reachable with configured credentials.",
      };
    } catch (error) {
      return {
        name: this.name,
        configured: true,
        status: "error",
        checkedAt: new Date().toISOString(),
        message: `Obsidian Local REST API health probe failed: ${error instanceof Error ? error.message : String(error)}`,
      };
    }
  }

  async searchVault(query: string): Promise<readonly VaultSearchHit[]> {
    const config = this.config();
    const trimmedQuery = query.trim();
    if (trimmedQuery.length === 0) {
      return [];
    }

    const response = await this.fetchWithTimeout(`${config.apiUrl}/search/simple/?query=${encodeURIComponent(trimmedQuery)}`, {
      method: "POST",
      body: "",
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

    const response = await this.fetchWithTimeout(`${config.apiUrl}/vault/${encodeVaultPath(notePath)}`, {
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

  async appendTasksToDailyNote(
    tasks: readonly ObsidianTaskWrite[],
    options: DailyNoteWriteOptions = {},
  ): Promise<DailyNoteWriteResult> {
    const config = this.config();
    const date = options.date ?? new Date();
    const path = normaliseNotePath(options.path ?? dailyNotePath(date, options.pathPattern));
    const heading = normaliseHeading(options.sectionHeading ?? "Capture");
    const lines = tasks.map(formatTasksPluginLine);
    if (lines.length === 0) {
      return { path, lines, writtenAt: new Date().toISOString() };
    }

    const note = await this.tryGetNote(config, path);
    const block = `${lines.join("\n")}\n`;
    if (!note) {
      const initial = `# ${dateStamp(date)}\n\n## ${heading}\n\n${block}`;
      await this.putNote(config, path, initial);
    } else if (hasHeading(note.content, heading)) {
      await this.patchNote(config, path, block, {
        Operation: "append",
        "Target-Type": "heading",
        Target: heading,
      });
    } else {
      await this.patchNote(config, path, `\n\n## ${heading}\n\n${block}`, {
        Operation: "append",
      });
    }

    return { path, lines, writtenAt: new Date().toISOString() };
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

  private async fetchWithTimeout(input: string, init: RequestInit): Promise<Response> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.requestTimeoutMs);
    try {
      return await this.fetchImpl(input, { ...init, signal: controller.signal });
    } finally {
      clearTimeout(timeout);
    }
  }

  private async tryGetNote(config: { apiUrl: string; apiKey: string }, path: string): Promise<VaultNote | null> {
    const response = await this.fetchWithTimeout(`${config.apiUrl}/vault/${encodeVaultPath(path)}`, {
      method: "GET",
      headers: authHeaders(config.apiKey, { Accept: "text/markdown, text/plain;q=0.9, */*;q=0.1" }),
    });
    if (response.status === 404) return null;
    await assertOk(response, "read Obsidian daily note");
    return {
      path,
      content: await response.text(),
      contentType: response.headers.get("content-type") ?? "text/markdown",
      retrievedAt: new Date().toISOString(),
    };
  }

  private async putNote(config: { apiUrl: string; apiKey: string }, path: string, content: string): Promise<void> {
    const response = await this.fetchWithTimeout(`${config.apiUrl}/vault/${encodeVaultPath(path)}`, {
      method: "PUT",
      body: content,
      headers: authHeaders(config.apiKey, { "Content-Type": "text/markdown" }),
    });
    await assertOk(response, "create Obsidian daily note");
  }

  private async patchNote(
    config: { apiUrl: string; apiKey: string },
    path: string,
    content: string,
    patchHeaders: Record<string, string>,
  ): Promise<void> {
    const response = await this.fetchWithTimeout(`${config.apiUrl}/vault/${encodeVaultPath(path)}`, {
      method: "PATCH",
      body: content,
      headers: authHeaders(config.apiKey, {
        "Content-Type": "text/markdown",
        ...patchHeaders,
      }),
    });
    await assertOk(response, "append to Obsidian daily note");
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

function normaliseNotePath(path: string): string {
  const trimmed = path.trim().replace(/^\/+/, "");
  if (trimmed.length === 0) throw new Error("Obsidian daily note path must be non-empty.");
  return trimmed.endsWith(".md") ? trimmed : `${trimmed}.md`;
}

function dailyNotePath(date: Date, pattern = "Daily/YYYY-MM-DD.md"): string {
  const yyyy = String(date.getFullYear());
  const mm = String(date.getMonth() + 1).padStart(2, "0");
  const dd = String(date.getDate()).padStart(2, "0");
  return pattern
    .replaceAll("YYYY", yyyy)
    .replaceAll("MM", mm)
    .replaceAll("DD", dd);
}

function dateStamp(date: Date): string {
  const yyyy = String(date.getFullYear());
  const mm = String(date.getMonth() + 1).padStart(2, "0");
  const dd = String(date.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

function normaliseHeading(value: string): string {
  const heading = value.replace(/^#+\s*/, "").trim();
  if (heading.length === 0) throw new Error("Obsidian daily note section heading must be non-empty.");
  return heading.slice(0, 120);
}

function hasHeading(content: string, heading: string): boolean {
  const escaped = heading.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`^#{1,6}\\s+${escaped}\\s*$`, "im").test(content);
}

function formatTasksPluginLine(task: ObsidianTaskWrite): string {
  const title = task.title.replace(/\s+/g, " ").trim();
  if (title.length === 0) throw new Error("Obsidian task title must be non-empty.");
  const done = task.completedAt ? "x" : " ";
  const parts = [`- [${done}] ${title}`];
  const tags = normaliseTags(task.tags);
  if (tags.length > 0) parts.push(tags.map((tag) => `#${tag}`).join(" "));
  const due = toDateStamp(task.dueAt);
  if (due) parts.push(`📅 ${due}`);
  const completed = toDateStamp(task.completedAt);
  if (completed) parts.push(`✅ ${completed}`);
  const priority = priorityMarker(task.priority);
  if (priority) parts.push(priority);
  return parts.join(" ");
}

function normaliseTags(tags: readonly string[] | undefined): string[] {
  if (!tags) return [];
  const out: string[] = [];
  for (const tag of tags) {
    const cleaned = tag.trim().toLowerCase().replace(/^#+/, "").replace(/[^a-z0-9/_-]+/g, "-").replace(/^-+|-+$/g, "");
    if (cleaned.length > 0 && !out.includes(cleaned)) out.push(cleaned);
  }
  return out.slice(0, 8);
}

function toDateStamp(value: Date | string | null | undefined): string | null {
  if (!value) return null;
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return dateStamp(date);
}

function priorityMarker(priority: number | null | undefined): string | null {
  if (priority === 0) return "⏫";
  if (priority === 1) return "🔼";
  if (priority === 3 || priority === 4) return "🔽";
  return null;
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
