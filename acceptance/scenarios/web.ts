import { webSession } from "../src/harness/web.js";
import { Report } from "../src/harness/report.js";
import { ensureTestAccount, syncDiagnostics } from "../src/harness/account.js";
import { sleep } from "../src/harness/uc.js";
import type { Safari } from "../src/harness/safari.js";

/**
 * Web acceptance: drives the real app (served locally in the sandbox, talking to production
 * backend + PowerSync) through the core capture-first lifecycle with screenshot evidence and
 * server-side cross-checks. Strings come from acceptance/features/web.md.
 */
async function signIn(safari: Safari, email: string, password: string): Promise<void> {
  await safari.type("Email", email);
  await safari.type("Password", password);
  await safari.submit("Sign In");
}

export async function run(): Promise<{ pass: number; fail: number; skip: number; total: number }> {
  const report = new Report("web");
  const account = await ensureTestAccount();
  report.log(`web acceptance · account ${account.email}`);
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
    await step("app-mounts-signin-gate", async () => {
      if (!(await safari.has("Sign In"))) throw new Error("sign-in gate not visible");
      return "sign-in gate visible";
    }, true);

    await step("auth-signin-password", async () => {
      await signIn(safari, account.email, account.password);
      let ok = false;
      for (let i = 0; i < 15 && !ok; i++) { await sleep(1500); ok = await safari.signedIn(); }
      if (!ok) throw new Error("main capture UI did not appear after sign-in");
      return "signed in; capture bar present";
    }, true);

    const capText = `web acceptance ${Date.now()}`;
    await step("capture-single", async () => {
      await sleep(4000); // let PowerSync settle its initial sync-down before the local write
      await safari.capture(capText);
      let appeared = false;
      for (let i = 0; i < 20 && !appeared; i++) {
        await sleep(2000);
        appeared = (await safari.count(".card-actions")) > 0 && (await safari.hasValue(capText));
      }
      if (!appeared) throw new Error("proposed confirm card did not appear");
      return `captured "${capText}" -> confirm card visible`;
    }, true);

    await step("capture-reflected-server-side", async () => {
      const d = await syncDiagnostics(account);
      if (d.server_counts.proposed < 1) throw new Error(`server shows ${d.server_counts.proposed} proposed`);
      return `server proposed=${d.server_counts.proposed}`;
    });

    await step("confirm-card-accept", async () => {
      await safari.click(".card-actions .primary"); // Confirm Y
      await sleep(2500);
      const d = await syncDiagnostics(account);
      if (d.server_counts.active < 1) throw new Error(`server shows ${d.server_counts.active} active after confirm`);
      return `confirmed -> server active=${d.server_counts.active}`;
    }, true);

    const rejectText = `web reject ${Date.now()}`;
    await step("confirm-card-reject", async () => {
      const before = (await syncDiagnostics(account)).server_counts.cancelled;
      await safari.capture(rejectText);
      let appeared = false;
      for (let i = 0; i < 20 && !appeared; i++) { await sleep(2000); appeared = (await safari.count(".card-actions")) > 0; }
      if (!appeared) throw new Error("confirm card for reject did not appear");
      await safari.click(".card-actions .ghost"); // Reject N
      await sleep(2500);
      const d = await syncDiagnostics(account);
      if (d.server_counts.cancelled <= before) throw new Error(`cancelled did not increase (was ${before}, now ${d.server_counts.cancelled})`);
      return `rejected -> server cancelled=${d.server_counts.cancelled}`;
    }, true);

    await step("open-settings", async () => {
      await safari.clickText("Settings", false);
      if (!(await safari.waitForText("Appearance", 8000))) throw new Error("settings did not open");
      return "settings visible (Appearance)";
    }, true);
  } finally {
    await web.close();
  }
  return report.finish();
}

// Allow running standalone: `tsx scenarios/web.ts`
if (import.meta.url === `file://${process.argv[1]}`) {
  run().then((c) => process.exit(c.fail > 0 ? 1 : 0));
}
