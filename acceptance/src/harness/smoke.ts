import { Computer } from "use-computer-sdk";
import { writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { config } from "./env.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPORT_DIR = resolve(__dirname, "../../reports");

/**
 * Smoke test: validate the use.computer key and provisioning path before the full
 * suite is built on top of it. Reads the platforms catalogue (cheap), then, unless
 * SMOKE_PLATFORMS_ONLY=1, boots a short-lived macOS sandbox and captures one screenshot.
 */
async function main() {
  mkdirSync(REPORT_DIR, { recursive: true });
  const client = new Computer({ apiKey: config.useComputerApiKey() });

  console.log("[smoke] querying platforms…");
  const platforms = await client.platforms();
  console.log("[smoke] platforms:", JSON.stringify(platforms, null, 2));

  if (config.raw.SMOKE_PLATFORMS_ONLY === "1") {
    console.log("[smoke] SMOKE_PLATFORMS_ONLY=1 — skipping sandbox boot. Key is valid.");
    return;
  }

  console.log("[smoke] creating macOS sandbox…");
  const mac = await client.create({ type: "macos" });
  try {
    console.log(`[smoke] sandbox ${mac.sandboxId} up. vnc=${mac.vncUrl}`);
    const info = await mac.displayInfo();
    console.log("[smoke] display:", info);
    const shot = await mac.screenshot.takeCompressed();
    const out = resolve(REPORT_DIR, "smoke-mac.png");
    writeFileSync(out, shot);
    console.log(`[smoke] screenshot ${shot.byteLength} bytes -> ${out}`);
    const whoami = await mac.execSsh("whoami && sw_vers -productVersion");
    console.log("[smoke] ssh whoami:", whoami.stdout.trim(), "exit", whoami.exitCode);
  } finally {
    await mac.close();
    console.log("[smoke] sandbox closed.");
  }
}

main().catch((err) => {
  console.error("[smoke] FAILED:", err instanceof Error ? err.message : err);
  process.exitCode = 1;
});
