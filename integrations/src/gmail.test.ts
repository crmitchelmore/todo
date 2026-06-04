import assert from "node:assert/strict";
import test from "node:test";

import {
  GmailConnector,
  GmailTransport,
  parseGmailSince,
  GMAIL_DEFAULT_HOST,
  GMAIL_DEFAULT_PORT,
} from "./gmail.js";
import {
  CompletionSignal,
  ExtractedTodo,
  IntegrationNotConfiguredError,
  TaskForCompletionDetection,
} from "./types.js";

test("unconfigured Gmail connector reports missing config", async () => {
  const connector = new GmailConnector({ user: undefined, appPassword: undefined });

  assert.equal(connector.isConfigured(), false);
  const health = await connector.healthCheck();
  assert.equal(health.status, "not_configured");
  assert.deepEqual(health.missingEnvVars, ["GMAIL_IMAP_USER", "GMAIL_IMAP_APP_PASSWORD or GMAIL_OAUTH_ACCESS_TOKEN"]);
});

test("unconfigured Gmail connector throws before IMAP calls", async () => {
  const connector = new GmailConnector({ user: undefined, appPassword: undefined });

  await assert.rejects(
    () => connector.extractTodos("7d"),
    (error: unknown) =>
      error instanceof IntegrationNotConfiguredError &&
      error.connector === "gmail" &&
      error.missingEnvVars.includes("GMAIL_IMAP_APP_PASSWORD or GMAIL_OAUTH_ACCESS_TOKEN"),
  );

  await assert.rejects(
    () => connector.detectCompletions([{ id: "task-1", title: "Reply to Sam" }]),
    IntegrationNotConfiguredError,
  );
});

test("configured connector defaults to Gmail IMAP host/port and reports ok", async () => {
  const connector = new GmailConnector({ user: "me@gmail.com", appPassword: "abcd efgh ijkl mnop" });
  assert.equal(connector.isConfigured(), true);
  const health = await connector.healthCheck();
  assert.equal(health.status, "ok");
  assert.match(health.message ?? "", new RegExp(`${GMAIL_DEFAULT_HOST}:${GMAIL_DEFAULT_PORT}`));
});

test("configured connector can use an OAuth2 access token instead of an app password", async () => {
  const connector = new GmailConnector({ user: "me@gmail.com", accessToken: "oauth-access-token" });
  assert.equal(connector.isConfigured(), true);
  const health = await connector.healthCheck();
  assert.equal(health.status, "ok");
  assert.match(health.message ?? "", /OAuth2/);
});

test("parseGmailSince understands relative and ISO specs", () => {
  const now = new Date("2026-06-02T12:00:00.000Z");
  assert.equal(parseGmailSince("7d", now).cutoff.toISOString(), "2026-05-26T12:00:00.000Z");
  assert.equal(parseGmailSince("12h", now).cutoff.toISOString(), "2026-06-02T00:00:00.000Z");
  assert.equal(parseGmailSince("2026-05-01", now).cutoff.toISOString(), "2026-05-01T00:00:00.000Z");
  assert.throws(() => parseGmailSince("  ", now));
  assert.throws(() => parseGmailSince("garbage", now));
});

test("Gmail type shapes round-trip through the transport boundary", async () => {
  const todo: ExtractedTodo = {
    source: "gmail",
    sourceMessageId: "message-123",
    threadId: "thread-123",
    title: "Send Chris the Capture update",
    sourceQuote: "Could you send me the Capture update tomorrow?",
    confidence: 0.92,
    sender: { name: "Chris", address: "chris@example.invalid" },
    receivedAt: "2026-06-02T00:00:00.000Z",
    dueHint: "tomorrow",
    labels: ["INBOX"],
  };
  const task: TaskForCompletionDetection = { id: "task-1", title: todo.title };
  const completion: CompletionSignal = {
    source: "gmail",
    taskId: task.id,
    messageId: "message-456",
    threadId: todo.threadId,
    reason: "Reply says the update was sent.",
    sourceQuote: "I've sent the Capture update.",
    confidence: 0.81,
    receivedAt: "2026-06-03T00:00:00.000Z",
  };

  const transport: GmailTransport = {
    async extractTodos(config, since) {
      assert.equal(config.host, GMAIL_DEFAULT_HOST);
      assert.equal(config.user, "me@gmail.com");
      assert.equal(config.rawSearch, "is:unread");
      assert.equal(since.spec, "7d");
      return [todo];
    },
    async fetchThread(config, threadId, since) {
      assert.equal(config.user, "me@gmail.com");
      assert.equal(threadId, "thread-123");
      assert.equal(since.spec, "14d");
      return [todo];
    },
    async detectCompletions(config, tasks) {
      assert.equal(config.appPassword, "app-password-placeholder");
      assert.deepEqual(tasks, [task]);
      return [completion];
    },
  };

  const connector = new GmailConnector({
    user: "me@gmail.com",
    appPassword: "app-password-placeholder",
    rawSearch: "is:unread",
    transport,
  });

  assert.equal(connector.isConfigured(), true);
  assert.deepEqual(await connector.extractTodos("7d"), [todo]);
  assert.deepEqual(await connector.fetchThread("thread-123", "14d"), [todo]);
  assert.deepEqual(await connector.detectCompletions([task]), [completion]);
  assert.deepEqual(JSON.parse(JSON.stringify(todo)), todo);
  assert.deepEqual(JSON.parse(JSON.stringify(completion)), completion);
});
