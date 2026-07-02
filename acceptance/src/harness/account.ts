import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { randomBytes } from "node:crypto";
import { config } from "./env.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ENV_PATH = resolve(__dirname, "../../.env.acceptance");

export interface TestAccount {
  email: string;
  password: string;
  userId: string;
  sessionToken: string;
}

export interface SyncDiagnostics {
  ok: boolean;
  owner: { id: string; email: string | null };
  server_counts: {
    total: number;
    proposed: number;
    active: number;
    done: number;
    cancelled: number;
    by_status: Record<string, number>;
    last_updated_at: string | null;
  };
  sessions: Array<{ client: string; sessions: number; active_sessions: number }>;
}

/** Update or append a KEY=VALUE line in the gitignored .env.acceptance so re-runs reuse the account. */
function persistEnv(key: string, value: string): void {
  let raw = "";
  try {
    raw = readFileSync(ENV_PATH, "utf8");
  } catch {
    /* file may not exist yet */
  }
  const lines = raw.split("\n");
  let found = false;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].startsWith(`${key}=`)) {
      lines[i] = `${key}=${value}`;
      found = true;
      break;
    }
  }
  if (!found) lines.push(`${key}=${value}`);
  writeFileSync(ENV_PATH, lines.join("\n"));
  config.raw[key] = value;
}

async function api<T>(path: string, init: RequestInit & { token?: string } = {}): Promise<T> {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (init.token) headers.Authorization = `Bearer ${init.token}`;
  const res = await fetch(`${config.backendUrl}${path}`, { ...init, headers: { ...headers, ...(init.headers as Record<string, string>) } });
  const text = await res.text();
  let json: unknown;
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    throw new Error(`${path} -> ${res.status} non-JSON: ${text.slice(0, 200)}`);
  }
  if (!res.ok) {
    throw new Error(`${path} -> ${res.status} ${JSON.stringify(json)}`);
  }
  return json as T;
}

/**
 * Register-or-login a stable, dedicated throwaway test account. Credentials are read from
 * ACCEPTANCE_ACCOUNT_EMAIL/PASSWORD; if absent they're generated once and persisted so the
 * suite is repeatable (re-runs sign into the same owner-scoped account).
 */
export async function ensureTestAccount(): Promise<TestAccount> {
  let email = config.account.email;
  let password = config.account.password;
  if (!email) {
    email = `capture-acceptance-${randomBytes(4).toString("hex")}@example.com`;
    persistEnv("ACCEPTANCE_ACCOUNT_EMAIL", email);
  }
  if (!password) {
    password = randomBytes(12).toString("base64url");
    persistEnv("ACCEPTANCE_ACCOUNT_PASSWORD", password);
  }

  try {
    const reg = await api<{ ok: boolean; session_token: string; user_id: string }>("/api/auth/register", {
      method: "POST",
      body: JSON.stringify({ email, password, client: "acceptance" }),
    });
    return { email, password, userId: reg.user_id, sessionToken: reg.session_token };
  } catch (err) {
    // 409 = already registered -> log in instead.
    const login = await api<{ ok: boolean; session_token?: string; user_id?: string; mfa_required?: boolean }>(
      "/api/auth/login",
      { method: "POST", body: JSON.stringify({ email, password, client: "acceptance" }) }
    );
    if (!login.session_token || !login.user_id) {
      throw new Error(`login did not return a session (mfa? ${login.mfa_required}). Original: ${String(err)}`);
    }
    return { email, password, userId: login.user_id, sessionToken: login.session_token };
  }
}

/** POST /api/capture as a signed-in client. Returns the created task id. */
export async function captureViaApi(
  account: TestAccount,
  input: { rawText: string; source?: string; agentMode?: "research" | "attempt"; agentPlanConfirmation?: boolean; url?: string; id?: string; parentTaskId?: string }
): Promise<{ id: string; created: boolean }> {
  const res = await api<{ ok: boolean; id: string; created: boolean }>("/api/capture", {
    method: "POST",
    token: account.sessionToken,
    body: JSON.stringify({
      id: input.id,
      raw_text: input.rawText,
      source: input.source ?? "capture",
      agent_mode: input.agentMode ?? "research",
      agent_plan_confirmation: input.agentPlanConfirmation ?? true,
      url: input.url,
      parent_task_id: input.parentTaskId,
    }),
  });
  return { id: res.id, created: res.created };
}

/** Apply a batch of client CRUD ops via PUT /api/data (how clients confirm/edit/reject/delete). */
export async function applyData(
  account: TestAccount,
  ops: Array<{ op: "PUT" | "PATCH" | "DELETE"; type: string; id: string; data?: Record<string, unknown> }>
): Promise<void> {
  await api("/api/data", { method: "PUT", token: account.sessionToken, body: JSON.stringify({ ops }) });
}

/** Confirm a proposed task -> active (mirrors the client confirm write path). */
export async function confirmViaApi(account: TestAccount, taskId: string, fields: Record<string, unknown> = {}): Promise<void> {
  await applyData(account, [
    { op: "PATCH", type: "tasks", id: taskId, data: { status: "active", confirmed_at: new Date().toISOString(), updated_at: new Date().toISOString(), ...fields } },
  ]);
}

/** Reject a proposed task -> cancelled. */
export async function rejectViaApi(account: TestAccount, taskId: string): Promise<void> {
  await applyData(account, [
    { op: "PATCH", type: "tasks", id: taskId, data: { status: "cancelled", updated_at: new Date().toISOString() } },
  ]);
}

/** Server-side status counts for the account (owner-scoped truth for counts). */
export async function syncDiagnostics(account: TestAccount): Promise<SyncDiagnostics> {
  return api<SyncDiagnostics>("/api/diagnostics/sync", { token: account.sessionToken });
}

/** Mint a short-lived PowerSync JWT + endpoint (used if a streaming reader is added later). */
export async function powersyncToken(account: TestAccount): Promise<{ token: string; powersync_url: string }> {
  return api("/api/auth/token", { token: account.sessionToken });
}
