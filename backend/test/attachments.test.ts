import assert from "node:assert/strict";
import test from "node:test";

import {
  ATTACHMENT_MAX_BYTES,
  validateAttachmentData,
} from "../src/attachments.ts";

const taskId = "11111111-1111-5111-8111-111111111111";

test("validateAttachmentData accepts bounded image preview rows", () => {
  const valid = validateAttachmentData({
    task_id: taskId,
    filename: " Screenshot.png ",
    mime_type: "image/jpeg",
    byte_size: 12,
    preview_data_url: "data:image/jpeg;base64,aGVsbG8=",
    created_at: "2026-06-04T19:00:00.000Z",
  });

  assert.deepEqual(valid, {
    task_id: taskId,
    filename: "Screenshot.png",
    mime_type: "image/jpeg",
    byte_size: 12,
    preview_data_url: "data:image/jpeg;base64,aGVsbG8=",
    created_at: "2026-06-04T19:00:00.000Z",
  });
});

test("validateAttachmentData rejects invalid or overlarge image rows before database constraints", () => {
  assert.equal(validateAttachmentData({ task_id: "bad", mime_type: "image/jpeg", byte_size: 1, preview_data_url: "data:image/jpeg;base64,aA==" }), null);
  assert.equal(validateAttachmentData({ task_id: taskId, mime_type: "text/plain", byte_size: 1, preview_data_url: "data:text/plain;base64,aA==" }), null);
  assert.equal(validateAttachmentData({ task_id: taskId, mime_type: "image/jpeg", byte_size: ATTACHMENT_MAX_BYTES + 1, preview_data_url: "data:image/jpeg;base64,aA==" }), null);
  assert.equal(validateAttachmentData({ task_id: taskId, mime_type: "image/png", byte_size: 1, preview_data_url: "data:image/jpeg;base64,aA==" }), null);
});
