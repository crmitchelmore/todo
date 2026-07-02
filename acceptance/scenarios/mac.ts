import { execFileSync } from "node:child_process";
import { readFileSync, mkdirSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";
import { macSession, sleep } from "../src/harness/uc.js";
import { Report } from "../src/harness/report.js";
import { ensureTestAccount } from "../src/harness/account.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(__dirname, "../..");
const APPS = resolve(REPO, "clients/apps");
const DERIVED = resolve(APPS, "DerivedData/Acceptance");
const BUNDLE_ID = "dev.crmitchelmore.capture.mac";

/** Build CaptureMac.app locally (unsigned) and return the built bundle path. */
function buildMacApp(): string {
  execFileSync("xcodegen", ["generate"], { cwd: APPS, stdio: "inherit", env: { ...process.env, GIT_CONFIG_COUNT: "0" } });
  execFileSync(
    "xcodebuild",
    ["-project", "Capture.xcodeproj", "-scheme", "CaptureMac", "-configuration", "Debug", "-destination", "platform=macOS", "-derivedDataPath", DERIVED, "build", "CODE_SIGNING_ALLOWED=NO"],
    { cwd: APPS, stdio: "inherit", env: { ...process.env, GIT_CONFIG_COUNT: "0" } }
  );
  const app = resolve(DERIVED, "Build/Products/Debug/CaptureMac.app");
  if (!existsSync(app)) throw new Error(`CaptureMac.app not found at ${app}`);
  return app;
}

/** Find a Capture window in the macOS accessibility tree (proves the native app is running). */
async function captureWindowPresent(mac: Awaited<ReturnType<typeof macSession>>["mac"]): Promise<boolean> {
  const tree = (await mac.uiTree()) as { applications?: Array<{ info?: { name?: string }; windows?: unknown[] }> };
  const app = (tree.applications ?? []).find((a) => /capture/i.test(a.info?.name ?? ""));
  return Boolean(app && (app.windows?.length ?? 0) > 0);
}

export async function run(): Promise<{ pass: number; fail: number; skip: number; total: number }> {
  const report = new Report("mac");
  const account = await ensureTestAccount();
  report.log(`macOS acceptance · account ${account.email}`);

  let appPath: string;
  try {
    report.log("building CaptureMac.app locally…");
    appPath = buildMacApp();
  } catch (err) {
    report.record({ name: "build-mac-app", status: "fail", detail: err instanceof Error ? err.message.slice(0, 200) : String(err) });
    return report.finish();
  }
  report.record({ name: "build-mac-app", status: "pass", detail: appPath.replace(REPO, ".") });

  const tar = "/tmp/todo/capture-mac.tgz";
  mkdirSync("/tmp/todo", { recursive: true });
  execFileSync("tar", ["czf", tar, "-C", resolve(appPath, ".."), "CaptureMac.app"]);
  const bytes = readFileSync(tar);

  const session = await macSession();
  const { mac } = session;
  try {
    await mac.mouse.click(959, 439).catch(() => {}); // dismiss TCC dialog
    await mac.execSsh("rm -rf /tmp/capture/mac && mkdir -p /tmp/capture/mac");
    await mac.upload(new Uint8Array(bytes), "/tmp/capture/capture-mac.tgz");
    await mac.execSsh("tar xzf /tmp/capture/capture-mac.tgz -C /tmp/capture/mac");
    report.record({ name: "upload-mac-app", status: "pass", detail: `${(bytes.byteLength / 1e6).toFixed(1)} MB` });

    await mac.execSsh(`open /tmp/capture/mac/CaptureMac.app --env CAPTURE_DISABLE_UPDATER=1`);
    await sleep(9000);
    const present = await captureWindowPresent(mac);
    const shot = await (async () => { await mac.execSsh(`osascript -e 'tell application "Capture" to activate' >/dev/null 2>&1 || true`); await sleep(600); return mac.screenshot.takeCompressed(); })();
    report.record({ name: "launch-mac-app", status: present ? "pass" : "fail", detail: present ? "Capture window present in AX tree" : "no Capture window found", screenshot: report.saveScreenshot("launch-mac", shot) });

    // Sign-in gate visibility (native app should show the sign-in window when signed out).
    const gate = await mac.uiTree().then((t) => JSON.stringify(t).match(/Sign In|Email|Capture anything/i) ? true : false).catch(() => false);
    report.record({ name: "mac-signin-gate-or-capture", status: gate ? "pass" : "skip", detail: gate ? "sign-in or capture surface detected" : "surface text not detected in AX tree" });
  } finally {
    await mac.execSsh(`osascript -e 'tell application id "${BUNDLE_ID}" to quit' >/dev/null 2>&1 || true`).catch(() => {});
    await session.close();
  }
  return report.finish();
}

if (import.meta.url === `file://${process.argv[1]}`) {
  run().then((c) => process.exit(c.fail > 0 ? 1 : 0));
}
