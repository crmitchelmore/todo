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

test("configured Obsidian connector health probes the live API boundary", async () => {
  const requests: { url: string; init?: RequestInit }[] = [];
  const fetchImpl = async (url: string | URL | Request, init?: RequestInit) => {
    requests.push({ url: String(url), init });
    return new Response(JSON.stringify({ status: "OK" }), { status: 200 });
  };
  const connector = new ObsidianConnector({
    apiUrl: "http://127.0.0.1:27123/",
    apiKey: "test-key",
    fetch: fetchImpl as typeof fetch,
  });

  const health = await connector.healthCheck();

  assert.equal(health.status, "ok");
  assert.equal(requests[0].url, "http://127.0.0.1:27123/");
  assert.equal((requests[0].init?.headers as Record<string, string>).Authorization, "Bearer test-key");
  assert.ok(requests[0].init?.signal instanceof AbortSignal);
});

test("Obsidian connector bounds vault calls with a timeout signal", async () => {
  const requests: { url: string; init?: RequestInit }[] = [];
  const fetchImpl = async (url: string | URL | Request, init?: RequestInit) => {
    requests.push({ url: String(url), init });
    if (String(url).includes("/search/simple/")) {
      return new Response(JSON.stringify([]), { status: 200 });
    }
    return new Response("# Capture\n", {
      status: 200,
      headers: { "content-type": "text/markdown" },
    });
  };
  const connector = new ObsidianConnector({
    apiUrl: "http://127.0.0.1:27123",
    apiKey: "test-key",
    fetch: fetchImpl as typeof fetch,
    requestTimeoutMs: 50,
  });

  await connector.searchVault("Capture");
  await connector.getNote("Projects/Capture.md");

  assert.match(requests[0].url, /\/search\/simple\/\?query=Capture$/);
  assert.equal(requests[0].init?.method, "POST");
  assert.equal(requests[0].init?.body, "");
  assert.ok(requests[0].init?.signal instanceof AbortSignal);
  assert.match(requests[1].url, /\/vault\/Projects\/Capture\.md$/);
  assert.ok(requests[1].init?.signal instanceof AbortSignal);
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
