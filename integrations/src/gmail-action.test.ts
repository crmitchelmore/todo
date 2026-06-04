import assert from "node:assert/strict";
import test from "node:test";

import {
  buildCompletionSignalsFromEmail,
  buildExtractedTodoFromEmail,
} from "./gmail-action.js";

test("Gmail action parser extracts sourced todo from actionable body text", () => {
  const todo = buildExtractedTodoFromEmail(
    {
      messageId: "message-1",
      threadId: "thread-1",
      subject: "Capture update",
      text: "Hi Chris, could you send me the Capture update tomorrow? Thanks.",
      date: new Date("2026-06-04T12:00:00.000Z"),
      fromAddress: { name: "Chris", address: "chris@example.invalid" },
      labels: ["INBOX", "IMPORTANT"],
    },
    42,
    "INBOX",
  );

  assert.ok(todo);
  assert.equal(todo.title, "Send me the Capture update tomorrow");
  assert.equal(todo.sourceQuote, "Hi Chris, could you send me the Capture update tomorrow?");
  assert.equal(todo.sourceMessageId, "message-1");
  assert.equal(todo.threadId, "thread-1");
  assert.equal(todo.dueHint, "tomorrow");
  assert.equal(todo.receivedAt, "2026-06-04T12:00:00.000Z");
  assert.deepEqual(todo.labels, ["INBOX", "IMPORTANT"]);
  assert.ok(todo.confidence >= 0.75);
});

test("Gmail action parser ignores informational mail without action language", () => {
  const todo = buildExtractedTodoFromEmail(
    {
      messageId: "message-2",
      subject: "FYI: release notes",
      text: "Sharing the release notes from yesterday. No action needed.",
    },
    43,
    "INBOX",
  );

  assert.equal(todo, null);
});

test("Gmail action parser handles subject-led action requests and fallback labels", () => {
  const todo = buildExtractedTodoFromEmail(
    {
      subject: "Action required: review the app store screenshots by Friday",
      html: "<p>Please ignore the duplicate attachment.</p>",
    },
    44,
    "INBOX",
  );

  assert.ok(todo);
  assert.equal(todo.title, "Review the app store screenshots by Friday");
  assert.equal(todo.sourceMessageId, "uid:44");
  assert.equal(todo.dueHint, "this week");
  assert.deepEqual(todo.labels, ["INBOX"]);
});

test("Gmail completion parser detects reply-based completion evidence", () => {
  const signals = buildCompletionSignalsFromEmail(
    {
      messageId: "message-3",
      threadId: "thread-3",
      subject: "Re: Capture update",
      text: "I've sent the Capture update and attached the screenshots.",
      date: new Date("2026-06-04T18:00:00.000Z"),
    },
    45,
    [
      { id: "task-1", title: "Send Capture update screenshots" },
      { id: "task-2", title: "Book dentist appointment" },
    ],
  );

  assert.equal(signals.length, 1);
  assert.equal(signals[0].taskId, "task-1");
  assert.equal(signals[0].threadId, "thread-3");
  assert.match(signals[0].reason, /completion phrase/);
  assert.equal(signals[0].sourceQuote, "I've sent the Capture update and attached the screenshots.");
  assert.ok(signals[0].confidence >= 0.7);
});

test("Gmail completion parser detects label-based completion evidence", () => {
  const signals = buildCompletionSignalsFromEmail(
    {
      subject: "App Store screenshots",
      text: "Latest screenshot thread.",
      labels: ["Capture/Done"],
    },
    46,
    [{ id: "task-3", title: "Review App Store screenshots" }],
  );

  assert.equal(signals.length, 1);
  assert.equal(signals[0].messageId, "uid:46");
  assert.match(signals[0].reason, /label/);
});
