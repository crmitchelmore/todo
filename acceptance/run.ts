import { spawn } from "node:child_process";
import { config } from "./src/harness/env.js";

/**
 * Repeatable acceptance runner. Usage:
 *   npx tsx run.ts [api|web|sync|evals|mac|ios|all]   (default: api web sync evals)
 * Sandbox suites (web/sync/mac/ios) need USE_COMPUTER_API_KEY; evals + the model-config test
 * additionally need ACCEPTANCE_LLM_*. Everything is skipped gracefully when prerequisites are absent.
 */
const SUITES: Record<string, { kind: "scenario" | "node-test"; path: string; needs: "uc" | "none" }> = {
  api: { kind: "node-test", path: "tests/api.test.ts", needs: "none" },
  web: { kind: "scenario", path: "scenarios/web.ts", needs: "uc" },
  sync: { kind: "scenario", path: "scenarios/sync.ts", needs: "uc" },
  mac: { kind: "scenario", path: "scenarios/mac.ts", needs: "uc" },
  ios: { kind: "scenario", path: "scenarios/ios.ts", needs: "uc" },
  evals: { kind: "scenario", path: "evals/run.ts", needs: "none" },
};

function ucConfigured(): boolean {
  return Boolean(config.raw.USE_COMPUTER_API_KEY);
}

function runChild(args: string[]): Promise<number> {
  return new Promise((resolve) => {
    const child = spawn("npx", ["tsx", ...args], { stdio: "inherit" });
    child.on("close", (code) => resolve(code ?? 1));
  });
}

async function main() {
  const requested = process.argv.slice(2);
  const suites = requested.length && !requested.includes("all") ? requested : ["api", "web", "sync", "evals"];
  const results: Array<{ suite: string; code: number | "skip" }> = [];

  for (const suite of suites) {
    const spec = SUITES[suite];
    if (!spec) {
      console.log(`[run] unknown suite "${suite}" — skipping`);
      continue;
    }
    if (spec.needs === "uc" && !ucConfigured()) {
      console.log(`[run] ${suite}: SKIP (needs USE_COMPUTER_API_KEY)`);
      results.push({ suite, code: "skip" });
      continue;
    }
    console.log(`\n===== ${suite} =====`);
    const code = spec.kind === "node-test" ? await runChild(["--test", spec.path]) : await runChild([spec.path]);
    results.push({ suite, code });
  }

  console.log("\n===== summary =====");
  let failed = false;
  for (const r of results) {
    const label = r.code === "skip" ? "SKIP" : r.code === 0 ? "PASS" : "FAIL";
    if (r.code !== "skip" && r.code !== 0) failed = true;
    console.log(`  ${label}  ${r.suite}`);
  }
  console.log("\nReports written under acceptance/reports/<suite>-<timestamp>/");
  process.exit(failed ? 1 : 0);
}

main();
