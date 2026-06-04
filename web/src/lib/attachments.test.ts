import assert from 'node:assert/strict';
import { test } from 'node:test';
import { dataUrlByteLength } from './attachments';

test('dataUrlByteLength decodes base64 payload size', () => {
  assert.equal(dataUrlByteLength('data:image/png;base64,SGVsbG8='), 5);
  assert.equal(dataUrlByteLength('data:image/jpeg;base64,AA=='), 1);
});

test('dataUrlByteLength returns zero for non-data-url payloads', () => {
  assert.equal(dataUrlByteLength('not-image-data'), 0);
});
