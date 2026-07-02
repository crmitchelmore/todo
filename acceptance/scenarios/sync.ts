import { webSession } from "../src/harness/web.js";
import { Report } from "../src/harness/report.js";
import { ensureTestAccount, captureViaApi, syncDiagnostics } from "../src/harness/account.js";
import { sleep } from "../src/harness/uc.js";

/**
 * Cross-surface sync: proves PowerSync propagates writes between independent clients against
 * production. Client A = backend API; Client B = the web app driven in the sandbox.
 *   A -> B : capture via API, assert it appears in the web UI (synced down).
 *   B -> server : capture in the web UI, assert the server reflects it (synced up).
 */
export async function run(): Promise<{ pass: number; fail: number; skip: number; total: number }> {
  const report = new Report("sync");
  const account = await ensureTestAccount();
  report.log(`sync acceptance · account ${account.email}`);
  const web = await webSession();
  const { safari } = web;

  async function step(name: string, fn: () => Promise<string | void>, shot = false): Promise<void> {
    const start = Date.now();
    try {
      const detail = (await fn()) || undefined;
      const screenshot = shot ? report.saveScreenshot(name, await web.screenshotApp()) : undefined;
      report.record({ name, status: "pass", detail, screenshot, durationMs: Date.now() - start });
    } catch (err) {
      const screenshot = report.saveScreenshot(`FAIL-${name}`, await web.screenshotApp().catch(() => new Uint8Array()));
      report.record({ name, status: "fail", detail: err instanceof Error ? err.message : String(err), screenshot, durationMs: Date.now() - start });
    }
  }

  try {
    await step("signed-in", async () => {
      await safari.type("Email", account.email);
      await safari.type("Password", account.password);
      await safari.submit("Sign In");
      let ok = false;
      for (let i = 0; i < 15 && !ok; i++) { await sleep(1500); ok = await safari.signedIn(); }
      if (!ok) throw new Error("not signed in");
      await sleep(4000); // let PowerSync connect
      return "web client B signed in";
    });

    const aToB = `sync A→B ${Date.now()}`;
    await step("sync-api-to-web (down)", async () => {
      await captureViaApi(account, { rawText: aToB }); // client A writes via backend
      let seen = false;
      for (let i = 0; i < 30 && !seen; i++) { await sleep(2000); seen = await safari.hasValue(aToB); }
      if (!seen) throw new Error(`API-captured item "${aToB}" did not sync into the web UI within 60s`);
      return `API capture appeared in web UI (PowerSync down-sync)`;
    }, true);

    const bToServer = `sync B→srv ${Date.now()}`;
    await step("sync-web-to-server (up)", async () => {
      const before = (await syncDiagnostics(account)).server_counts.proposed;
      await safari.capture(bToServer);
      let ok = false;
      for (let i = 0; i < 30 && !ok; i++) {
        await sleep(2000);
        ok = (await syncDiagnostics(account)).server_counts.proposed > before;
      }
      if (!ok) throw new Error("web capture did not reach the server within 60s");
      return "web capture reflected on server (PowerSync up-sync)";
    }, true);
  } finally {
    await web.close();
  }
  return report.finish();
}

if (import.meta.url === `file://${process.argv[1]}`) {
  run().then((c) => process.exit(c.fail > 0 ? 1 : 0));
}
