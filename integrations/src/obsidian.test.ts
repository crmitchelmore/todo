import assert from "node:assert/strict";
import test from "node:test";

import { ObsidianConnector } from "./obsidian.js";
import { IntegrationNotConfiguredError, VaultNote, VaultSearchHit } from "./types.js";

test("unconfigured Obsidian connector reports missing config", async () => {
  const connector = new ObsidianConnector({ apiUrl: undefined, apiKey: undefined });

  assert.equal(connector.isConfigured(), false);
  const health = await connector.healthCheck();
  assert.equal(health.status, "not_configured");
  assert.deepEqual(health.missingEnvVars, ["OBSIDIAN_API_URL", "OBSIDIAN_API_KEY"]);
});

test("unconfigured Obsidian connector throws before vault calls", async () => {
  const connector = new ObsidianConnector({ apiUrl: undefined, apiKey: undefined });

  await assert.rejects(
    () => connector.searchVault("project"),
    (error: unknown) =>
      error instanceof IntegrationNotConfiguredError &&
      error.connector === "obsidian" &&
      error.missingEnvVars.includes("OBSIDIAN_API_KEY"),
  );

  await assert.rejects(
    () => connector.getNote("Projects/Capture.md"),
    IntegrationNotConfiguredError,
  );
});

test("Obsidian search and note type shapes round-trip", async () => {
  const hit: VaultSearchHit = {
    path: "Projects/Capture.md",
    score: 0.87,
    excerpt: "Capture todo context",
    matches: [{ context: "Capture todo context", position: { start: 0, end: 7 } }],
  };
  const note: VaultNote = {
    path: hit.path,
    content: "# Capture\n\n- [ ] Follow up",
    contentType: "text/markdown",
    retrievedAt: "2026-06-02T00:00:00.000Z",
  };

  assert.deepEqual(JSON.parse(JSON.stringify(hit)), hit);
  assert.deepEqual(JSON.parse(JSON.stringify(note)), note);
});
