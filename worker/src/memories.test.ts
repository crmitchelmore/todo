import assert from 'node:assert/strict';
import test from 'node:test';

import { ACTIVE_MEMORIES_SQL, compactMemories, loadActiveMemories, mapMemoryRow } from './memories.js';

test('active memories query excludes disabled deleted and expired rows', () => {
  assert.match(ACTIVE_MEMORIES_SQL, /status = 'active'/);
  assert.match(ACTIVE_MEMORIES_SQL, /expires_at IS NULL OR expires_at > now\(\)/);
  assert.match(ACTIVE_MEMORIES_SQL, /ORDER BY confidence DESC, updated_at DESC/);
  assert.match(ACTIVE_MEMORIES_SQL, /LIMIT 24/);
});

test('loadActiveMemories maps rows with tags and normalises timestamptz dates', async () => {
  const calls: Array<{ sql: string; params: unknown[] }> = [];
  const fakePool = {
    async query(sql: string, params: unknown[]) {
      calls.push({ sql, params });
      return {
        rows: [
          {
            content: 'Prefers buy-it-for-life cookware.',
            domain: 'shopping',
            source: 'manual',
            confidence: 0.9,
            tags: '["kitchen","shopping"]',
            expires_at: new Date('2026-07-01T00:00:00.000Z'),
          },
        ],
      };
    },
  };

  const memories = await loadActiveMemories(fakePool as any, 'owner-1');

  assert.equal(calls.length, 1);
  assert.equal(calls[0].sql, ACTIVE_MEMORIES_SQL);
  assert.deepEqual(calls[0].params, ['owner-1']);
  assert.deepEqual(memories, [
    {
      content: 'Prefers buy-it-for-life cookware.',
      domain: 'shopping',
      source: 'manual',
      confidence: 0.9,
      tags: ['kitchen', 'shopping'],
      expiresAt: '2026-07-01T00:00:00.000Z',
    },
  ]);
});

test('mapMemoryRow tolerates malformed tags', () => {
  const memory = mapMemoryRow({
    content: 'Use fast delivery.',
    domain: null,
    source: 'manual',
    confidence: 1,
    tags: 'not-json',
    expires_at: null,
  });

  assert.deepEqual(memory.tags, []);
});

test('compactMemories bounds memory metadata for task event payloads', () => {
  const compacted = compactMemories(Array.from({ length: 8 }, (_, i) => ({
    content: `${i}-` + 'x'.repeat(500),
    domain: 'shopping',
    source: 'manual',
    confidence: 1,
    tags: ['a', 'b', 'c', 'd', 'e', 'f', 'g'],
    expiresAt: null,
  })));

  assert.equal(compacted.length, 5);
  assert.equal(String(compacted[0].content).length, 220);
  assert.deepEqual(compacted[0].tags, ['a', 'b', 'c', 'd', 'e', 'f']);
});
