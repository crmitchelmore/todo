import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { ensureTestAccount, captureViaApi, confirmViaApi, rejectViaApi, applyData, syncDiagnostics, type TestAccount } from "../src/harness/account.js";
import { config } from "../src/harness/env.js";

/**
 * Deterministic acceptance for the production backend write path. Fast, no sandbox.
 * Delta-based assertions (the dedicated account accumulates state across runs).
 */
let account: TestAccount;

test("register-or-login yields a session for the dedicated account", async () => {
  account = await ensureTestAccount();
  assert.ok(account.sessionToken.length > 10, "session token issued");
  assert.match(account.userId, /^[0-9a-f-]{36}$/i, "user id is a uuid");
});

test("D1 capture creates a proposed task (proposed count +1)", async () => {
  const before = (await syncDiagnostics(account)).server_counts.proposed;
  const res = await captureViaApi(account, { rawText: `api d1 ${Date.now()}` });
  assert.equal(res.created, true, "capture created a row");
  const after = (await syncDiagnostics(account)).server_counts.proposed;
  assert.equal(after, before + 1, "proposed incremented by exactly 1");
});

test("capture is idempotent on client id (second POST does not create)", async () => {
  const id = randomUUID();
  const first = await captureViaApi(account, { rawText: `api idem ${Date.now()}`, id });
  const second = await captureViaApi(account, { rawText: "ignored duplicate", id });
  assert.equal(first.created, true);
  assert.equal(second.created, false, "duplicate id is a no-op");
});

test("D10 confirm moves proposed -> active", async () => {
  const cap = await captureViaApi(account, { rawText: `api confirm ${Date.now()}` });
  const before = (await syncDiagnostics(account)).server_counts.active;
  await confirmViaApi(account, cap.id);
  const after = (await syncDiagnostics(account)).server_counts.active;
  assert.equal(after, before + 1, "active incremented after confirm");
});

test("D14 reject moves proposed -> cancelled", async () => {
  const cap = await captureViaApi(account, { rawText: `api reject ${Date.now()}` });
  const before = (await syncDiagnostics(account)).server_counts.cancelled;
  await rejectViaApi(account, cap.id);
  const after = (await syncDiagnostics(account)).server_counts.cancelled;
  assert.equal(after, before + 1, "cancelled incremented after reject");
});

test("empty capture is rejected (400)", async () => {
  await assert.rejects(
    () => captureViaApi(account, { rawText: "   " }),
    /40[0-9]/,
    "empty capture should 400"
  );
});

test("D18 agent handoff queues a research request (202 + request_id)", async () => {
  const cap = await captureViaApi(account, { rawText: `api handoff ${Date.now()}` });
  const res = await fetch(`${config.backendUrl}/api/tasks/${cap.id}/agent-handoff`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${account.sessionToken}` },
    body: JSON.stringify({ mode: "research", instructions: "look for the fastest safe path" }),
  });
  assert.equal(res.status, 202, "handoff accepted");
  const json = (await res.json()) as { ok: boolean; request_id?: string };
  assert.ok(json.request_id, "handoff returns a request_id");
});

test("D20 proposal decision validates the decision value (400 on garbage)", async () => {
  const res = await fetch(`${config.backendUrl}/api/agent/proposals/${randomUUID()}/decision`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${account.sessionToken}` },
    body: JSON.stringify({ decision: "maybe" }),
  });
  assert.equal(res.status, 400, "invalid decision is a 400");
});

test("auth rejects a wrong password (401)", async () => {
  const res = await fetch(`${config.backendUrl}/api/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: account.email, password: "definitely-not-the-password" }),
  });
  assert.equal(res.status, 401, "wrong password is a 401");
});

test("owner scoping: cannot mutate a random non-owned task id (no-op, counts unchanged)", async () => {
  const before = (await syncDiagnostics(account)).server_counts;
  await applyData(account, [{ op: "PATCH", type: "tasks", id: randomUUID(), data: { status: "done" } }]);
  const after = (await syncDiagnostics(account)).server_counts;
  assert.deepEqual(after.by_status, before.by_status, "counts unchanged for a non-owned id");
});
