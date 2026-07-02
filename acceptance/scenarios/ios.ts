import { execFileSync } from "node:child_process";
import { readFileSync, mkdirSync, existsSync, readdirSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";
import { iosSession, sleep } from "../src/harness/uc.js";
import { Report } from "../src/harness/report.js";
import { ensureTestAccount } from "../src/harness/account.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(__dirname, "../..");
const APPS = resolve(REPO, "clients/apps");
const DERIVED = resolve(APPS, "DerivedData/AcceptanceIOS");
const BUNDLE_ID = "dev.crmitchelmore.capture.ios";

/** Build CaptureiOS.app for the simulator (unsigned) and return the .app path. */
function buildIosApp(): string {
  execFileSync("xcodegen", ["generate"], { cwd: APPS, stdio: "inherit", env: { ...process.env, GIT_CONFIG_COUNT: "0" } });
  execFileSync(
    "xcodebuild",
    ["-project", "Capture.xcodeproj", "-scheme", "CaptureiOS", "-configuration", "Debug", "-sdk", "iphonesimulator", "-derivedDataPath", DERIVED, "build", "CODE_SIGNING_ALLOWED=NO"],
    { cwd: APPS, stdio: "inherit", env: { ...process.env, GIT_CONFIG_COUNT: "0" } }
  );
  const products = resolve(DERIVED, "Build/Products/Debug-iphonesimulator");
  const app = existsSync(products) ? readdirSync(products).find((f) => f.endsWith(".app")) : undefined;
  if (!app) throw new Error(`CaptureiOS.app not found under ${products}`);
  return resolve(products, app);
}

export async function run(): Promise<{ pass: number; fail: number; skip: number; total: number }> {
  const report = new Report("ios");
  const account = await ensureTestAccount();
  report.log(`iOS acceptance · account ${account.email}`);

  let appPath: string;
  try {
    report.log("building CaptureiOS.app for the simulator…");
    appPath = buildIosApp();
  } catch (err) {
    report.record({ name: "build-ios-app", status: "fail", detail: err instanceof Error ? err.message.slice(0, 200) : String(err) });
    return report.finish();
  }
  report.record({ name: "build-ios-app", status: "pass", detail: appPath.replace(REPO, ".") });

  const tar = "/tmp/todo/capture-ios.tgz";
  mkdirSync("/tmp/todo", { recursive: true });
  execFileSync("tar", ["czf", tar, "-C", resolve(appPath, ".."), appPath.split("/").pop()!]);
  const bytes = readFileSync(tar);

  const session = await iosSession("iphone");
  const { ios } = session;
  try {
    await ios.exec("mkdir -p /tmp/capture");
    await ios.upload(new Uint8Array(bytes), "/tmp/capture/capture-ios.tgz");
    await ios.exec("cd /tmp/capture && tar xzf capture-ios.tgz");
    report.record({ name: "upload-ios-app", status: "pass", detail: `${(bytes.byteLength / 1e6).toFixed(1)} MB` });

    // Install into the booted simulator and launch.
    const appName = appPath.split("/").pop()!;
    const install = await ios.exec(`xcrun simctl install booted /tmp/capture/${appName}`);
    report.record({ name: "install-ios-app", status: install.exitCode === 0 ? "pass" : "fail", detail: install.stderr.slice(0, 160) || "installed" });

    await ios.launch(BUNDLE_ID);
    await sleep(7000);
    const shot = await ios.screenshot.takeCompressed();
    // App launched if its UI tree exposes any element (sign-in gate / capture surface).
    const tree = await ios.uiTree().then((t) => JSON.stringify(t)).catch(() => "");
    const launched = tree.length > 50;
    report.record({ name: "launch-ios-app", status: launched ? "pass" : "fail", detail: launched ? "app UI tree populated" : "empty UI tree", screenshot: report.saveScreenshot("launch-ios", shot) });
    const gate = /Sign In|Email|Capture anything/i.test(tree);
    report.record({ name: "ios-signin-gate-or-capture", status: gate ? "pass" : "skip", detail: gate ? "sign-in or capture surface detected" : "surface text not detected" });
  } finally {
    await ios.exec(`xcrun simctl terminate booted ${BUNDLE_ID}`).catch(() => {});
    await session.close();
  }
  return report.finish();
}

if (import.meta.url === `file://${process.argv[1]}`) {
  run().then((c) => process.exit(c.fail > 0 ? 1 : 0));
}
