import assert from "node:assert/strict";
import test from "node:test";

import { GmailConnector, GMAIL_READONLY_SCOPE, GmailTransport } from "./gmail.js";
import {
  CompletionSignal,
  ExtractedTodo,
  IntegrationNotConfiguredError,
  TaskForCompletionDetection,
} from "./types.js";

test("unconfigured Gmail connector reports missing config", async () => {
  const connector = new GmailConnector({ clientId: undefined, clientSecret: undefined, refreshToken: undefined });

  assert.equal(connector.isConfigured(), false);
  const health = await connector.healthCheck();
  assert.equal(health.status, "not_configured");
  assert.deepEqual(health.missingEnvVars, ["GMAIL_CLIENT_ID", "GMAIL_CLIENT_SECRET", "GMAIL_REFRESH_TOKEN"]);
});

test("unconfigured Gmail connector throws before extraction calls", async () => {
  const connector = new GmailConnector({ clientId: undefined, clientSecret: undefined, refreshToken: undefined });

  await assert.rejects(
    () => connector.extractTodos("newer_than:7d"),
    (error: unknown) =>
      error instanceof IntegrationNotConfiguredError &&
      error.connector === "gmail" &&
      error.missingEnvVars.includes("GMAIL_REFRESH_TOKEN"),
  );

  await assert.rejects(
    () => connector.detectCompletions([{ id: "task-1", title: "Reply to Sam" }]),
    IntegrationNotConfiguredError,
  );
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
    async extractTodos(config, sinceQuery) {
      assert.equal(config.scopes[0], GMAIL_READONLY_SCOPE);
      assert.equal(sinceQuery, "newer_than:7d");
      return [todo];
    },
    async detectCompletions(config, tasks) {
      assert.equal(config.scopes[0], GMAIL_READONLY_SCOPE);
      assert.deepEqual(tasks, [task]);
      return [completion];
    },
  };

  const connector = new GmailConnector({
    clientId: "client-id-placeholder",
    clientSecret: "client-secret-placeholder",
    refreshToken: "refresh-token-placeholder",
    transport,
  });

  assert.equal(connector.isConfigured(), true);
  assert.deepEqual(await connector.extractTodos("newer_than:7d"), [todo]);
  assert.deepEqual(await connector.detectCompletions([task]), [completion]);
  assert.deepEqual(JSON.parse(JSON.stringify(todo)), todo);
  assert.deepEqual(JSON.parse(JSON.stringify(completion)), completion);
});
