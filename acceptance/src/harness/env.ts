import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ENV_PATH = resolve(__dirname, "../../.env.acceptance");

/**
 * Minimal .env loader (no dependency). Values already present in process.env win,
 * so CI can override the gitignored file. Never logs values.
 */
export function loadEnv(): Record<string, string> {
  const out: Record<string, string> = {};
  try {
    const raw = readFileSync(ENV_PATH, "utf8");
    for (const line of raw.split("\n")) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const eq = trimmed.indexOf("=");
      if (eq === -1) continue;
      const key = trimmed.slice(0, eq).trim();
      const value = trimmed.slice(eq + 1).trim();
      if (key) out[key] = value;
    }
  } catch {
    // No .env.acceptance file — rely on process.env only.
  }
  for (const [k, v] of Object.entries(process.env)) {
    if (v !== undefined) out[k] = v;
  }
  return out;
}

const env = loadEnv();

function required(name: string): string {
  const v = env[name];
  if (!v) throw new Error(`Missing required env ${name} (set it in acceptance/.env.acceptance)`);
  return v;
}

function optional(name: string, fallback = ""): string {
  return env[name] ?? fallback;
}

export const config = {
  useComputerApiKey: () => required("USE_COMPUTER_API_KEY"),
  webUrl: optional("CAPTURE_WEB_URL", "https://web-production-9267a.up.railway.app"),
  backendUrl: optional("CAPTURE_BACKEND_URL", "https://backend-production-de2f.up.railway.app"),
  powersyncUrl: optional("CAPTURE_POWERSYNC_URL", "https://powersync-production-e560.up.railway.app"),
  account: {
    email: optional("ACCEPTANCE_ACCOUNT_EMAIL"),
    password: optional("ACCEPTANCE_ACCOUNT_PASSWORD"),
  },
  llm: {
    apiKey: optional("ACCEPTANCE_LLM_API_KEY"),
    baseUrl: optional("ACCEPTANCE_LLM_BASE_URL", "https://api.openai.com/v1"),
    model: optional("ACCEPTANCE_LLM_MODEL", "gpt-4o-mini"),
    enabled: () => Boolean(optional("ACCEPTANCE_LLM_API_KEY")),
  },
  raw: env,
};
