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

test("Obsidian connector creates a daily note with Tasks-format lines", async () => {
  const requests: { url: string; init?: RequestInit }[] = [];
  const fetchImpl = async (url: string | URL | Request, init?: RequestInit) => {
    requests.push({ url: String(url), init });
    if (init?.method === "GET") return new Response("not found", { status: 404, statusText: "Not Found" });
    return new Response("", { status: 200 });
  };
  const connector = new ObsidianConnector({
    apiUrl: "http://127.0.0.1:27123",
    apiKey: "test-key",
    fetch: fetchImpl as typeof fetch,
  });

  const result = await connector.appendTasksToDailyNote(
    [{
      title: "Review Capture inbox",
      dueAt: "2026-06-05T09:00:00.000Z",
      tags: ["Capture", "Inbox"],
      priority: 1,
    }],
    { date: new Date("2026-06-04T12:00:00.000Z") },
  );

  assert.equal(result.path, "Daily/2026-06-04.md");
  assert.deepEqual(result.lines, ["- [ ] Review Capture inbox #capture #inbox 📅 2026-06-05 🔼"]);
  assert.equal(requests[1].init?.method, "PUT");
  assert.match(String(requests[1].init?.body), /## Capture/);
  assert.match(String(requests[1].init?.body), /- \[ \] Review Capture inbox #capture #inbox 📅 2026-06-05 🔼/);
});

test("Obsidian connector appends under existing daily note heading", async () => {
  const requests: { url: string; init?: RequestInit }[] = [];
  const fetchImpl = async (url: string | URL | Request, init?: RequestInit) => {
    requests.push({ url: String(url), init });
    if (init?.method === "GET") {
      return new Response("# 2026-06-04\n\n## Capture\n\nExisting", { status: 200 });
    }
    return new Response("", { status: 200 });
  };
  const connector = new ObsidianConnector({
    apiUrl: "http://127.0.0.1:27123",
    apiKey: "test-key",
    fetch: fetchImpl as typeof fetch,
  });

  await connector.appendTasksToDailyNote(
    [{ title: "Ship TestFlight build", completedAt: "2026-06-04T19:00:00.000Z", tags: ["ios"] }],
    { path: "Journal/2026-06-04", sectionHeading: "## Capture" },
  );

  assert.equal(requests[1].init?.method, "PATCH");
  assert.equal((requests[1].init?.headers as Record<string, string>).Operation, "append");
  assert.equal((requests[1].init?.headers as Record<string, string>)["Target-Type"], "heading");
  assert.equal((requests[1].init?.headers as Record<string, string>).Target, "Capture");
  assert.equal(requests[1].init?.body, "- [x] Ship TestFlight build #ios ✅ 2026-06-04\n");
});
