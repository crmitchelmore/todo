import assert from 'node:assert/strict';
import { test } from 'node:test';

import { cleanUserMemoryInput, parseMemoryExpiry } from './userMemoryModel';

test('cleanUserMemoryInput trims bounds and normalises memory writes', () => {
  const cleaned = cleanUserMemoryInput({
    content: `  ${'x'.repeat(1200)}  `,
    domain: ` ${'shopping'.repeat(20)} `,
    source: 'manual',
    confidence: 3,
    tags: [' Kitchen Stuff ', 'kitchen-stuff', 'fast delivery'],
    status: 'nonsense' as any,
    expires_at: null,
  });

  assert.ok(cleaned);
  assert.equal(cleaned.content.length, 1000);
  assert.equal(cleaned.domain?.length, 80);
  assert.equal(cleaned.confidence, 1);
  assert.deepEqual(cleaned.tags, ['Kitchen Stuff', 'kitchen-stuff', 'fast delivery']);
  assert.equal(cleaned.status, 'active');
});

test('cleanUserMemoryInput rejects empty content', () => {
  assert.equal(cleanUserMemoryInput({ content: '   ', domain: null, tags: [], expires_at: null }), null);
});

test('parseMemoryExpiry returns ISO end-of-day or null', () => {
  assert.equal(parseMemoryExpiry(''), null);
  assert.equal(parseMemoryExpiry('not-a-date'), null);
  assert.equal(parseMemoryExpiry('2026-07-01'), '2026-07-01T23:59:59.000Z');
});
