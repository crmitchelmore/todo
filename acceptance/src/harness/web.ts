import { execFileSync } from "node:child_process";
import { readFileSync, existsSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";
import { macSession, sleep, type MacSession } from "./uc.js";
import { Safari } from "./safari.js";
import { config } from "./env.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(__dirname, "../../..");
const WEB_DIR = resolve(REPO, "web");
const WEB_DIST = resolve(WEB_DIR, "dist");
const PORT = 4599;

/**
 * Build the web app locally with the production backend/powersync baked in. Serving it inside
 * the sandbox (instead of the flaky Railway web edge) is what makes web driving repeatable; the
 * app still talks to the real production backend + PowerSync, so sync is genuinely exercised.
 */
export function buildWebDist(force = false): void {
  if (!force && existsSync(resolve(WEB_DIST, "index.html"))) return;
  execFileSync("npm", ["run", "build"], {
    cwd: WEB_DIR,
    stdio: "inherit",
    env: {
      ...process.env,
      VITE_BACKEND_URL: config.backendUrl,
      VITE_POWERSYNC_URL: config.powersyncUrl,
    },
  });
}

export interface WebSession {
  session: MacSession;
  safari: Safari;
  /** Activate Safari, size its window to the screen, and capture a full-screen PNG. */
  screenshotApp(): Promise<Uint8Array>;
  close(): Promise<void>;
}

/** Boot a macOS sandbox, dismiss chrome, serve the built web app locally, and open it in Safari. */
export async function webSession(): Promise<WebSession> {
  buildWebDist();
  const tar = "/tmp/todo/web-dist.tgz";
  mkdirSync("/tmp/todo", { recursive: true });
  execFileSync("tar", ["czf", tar, "-C", WEB_DIST, "."]);
  const bytes = readFileSync(tar);

  const session = await macSession();
  const { mac } = session;

  // Dismiss the recurring TCC screen-recording dialog (covers Safari in screenshots) and banners.
  await mac.mouse.click(959, 439).catch(() => {}); // "Allow" on the centered system dialog
  await mac.execSsh(`osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true`);

  await mac.execSsh("rm -rf /tmp/capture/web && mkdir -p /tmp/capture/web");
  await mac.upload(new Uint8Array(bytes), "/tmp/capture/web-dist.tgz");
  await mac.execSsh("tar xzf /tmp/capture/web-dist.tgz -C /tmp/capture/web");
  await mac.execSsh(`pkill -f "http.server ${PORT}" >/dev/null 2>&1 || true`);
  await mac.execSsh(`cd /tmp/capture/web && nohup python3 -m http.server ${PORT} >/tmp/capture/http.log 2>&1 &`);
  await sleep(1500);

  const safari = new Safari(mac, `http://localhost:${PORT}`);
  await safari.setup();
  await safari.open("/");
  await maximizeSafari(mac);

  const screenshotApp = async (): Promise<Uint8Array> => {
    await mac.execSsh(`osascript -e 'tell application "Safari" to activate'`).catch(() => {});
    await sleep(600);
    return mac.screenshot.takeCompressed();
  };

  return {
    session,
    safari,
    screenshotApp,
    close: () => session.close(),
  };
}

async function maximizeSafari(mac: MacSession["mac"]): Promise<void> {
  const disp = await mac.displayInfo().catch(() => ({ width: 1920, height: 1080 } as { width: number; height: number }));
  const w = (disp as { width: number }).width ?? 1920;
  const h = (disp as { height: number }).height ?? 1080;
  await mac
    .execSsh(
      `osascript -e 'tell application "Safari" to set bounds of front window to {0, 25, ${w}, ${h}}'`
    )
    .catch(() => {});
}
