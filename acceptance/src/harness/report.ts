import { mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPORT_DIR = resolve(__dirname, "../../reports");

/** Redact anything that looks like a use.computer / bearer token before it is logged or written. */
export function redact(text: string): string {
  return text
    .replace(/uc_live_[A-Za-z0-9]+/g, "uc_live_***")
    .replace(/(token=)[A-Za-z0-9._-]+/g, "$1***")
    .replace(/(Bearer )[A-Za-z0-9._-]+/g, "$1***")
    .replace(/(ACCEPTANCE_LLM_API_KEY=)[^\s]+/g, "$1***");
}

export interface StepResult {
  name: string;
  status: "pass" | "fail" | "skip";
  detail?: string;
  screenshot?: string;
  durationMs?: number;
}

export class Report {
  readonly runId: string;
  readonly dir: string;
  private steps: StepResult[] = [];
  private startedAt = Date.now();

  constructor(suite: string) {
    this.runId = `${suite}-${new Date().toISOString().replace(/[:.]/g, "-")}`;
    this.dir = resolve(REPORT_DIR, this.runId);
    mkdirSync(this.dir, { recursive: true });
  }

  log(message: string): void {
    // Always redact secrets from any console output the harness produces.
    console.log(redact(message));
  }

  saveScreenshot(name: string, png: Uint8Array): string {
    const file = `${name.replace(/[^a-z0-9._-]/gi, "_")}.png`;
    writeFileSync(resolve(this.dir, file), png);
    return file;
  }

  record(step: StepResult): void {
    this.steps.push(step);
    const glyph = step.status === "pass" ? "✓" : step.status === "skip" ? "◦" : "✗";
    this.log(`  ${glyph} ${step.name}${step.detail ? ` — ${step.detail}` : ""}`);
  }

  get counts() {
    return {
      pass: this.steps.filter((s) => s.status === "pass").length,
      fail: this.steps.filter((s) => s.status === "fail").length,
      skip: this.steps.filter((s) => s.status === "skip").length,
      total: this.steps.length,
    };
  }

  finish(): { pass: number; fail: number; skip: number; total: number } {
    const c = this.counts;
    const md = [
      `# Acceptance run: ${this.runId}`,
      "",
      `Duration: ${((Date.now() - this.startedAt) / 1000).toFixed(1)}s · ${c.pass} pass · ${c.fail} fail · ${c.skip} skip`,
      "",
      "| # | step | status | detail | screenshot |",
      "|---|------|--------|--------|------------|",
      ...this.steps.map((s, i) =>
        `| ${i + 1} | ${s.name} | ${s.status} | ${redact(s.detail ?? "")} | ${s.screenshot ?? ""} |`
      ),
      "",
    ].join("\n");
    writeFileSync(resolve(this.dir, "report.md"), md);
    writeFileSync(resolve(this.dir, "report.json"), JSON.stringify({ runId: this.runId, counts: c, steps: this.steps }, null, 2));
    this.log(`report -> ${resolve(this.dir, "report.md")}`);
    return c;
  }
}
