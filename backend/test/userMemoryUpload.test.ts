import assert from 'node:assert/strict';
import test from 'node:test';

import { normalizeUserMemoryWrite, softDeleteUserMemory } from '../src/userMemoryUpload.js';

test('normalizeUserMemoryWrite defaults unknown status to active and clears deleted_at', () => {
  const data: Record<string, unknown> = { status: 'weird', deleted_at: '2026-01-01T00:00:00Z' };

  normalizeUserMemoryWrite(data);

  assert.equal(data.status, 'active');
  assert.equal(data.deleted_at, null);
});

test('normalizeUserMemoryWrite preserves disabled and clears deleted_at', () => {
  const data: Record<string, unknown> = { status: 'disabled', deleted_at: '2026-01-01T00:00:00Z' };

  normalizeUserMemoryWrite(data);

  assert.equal(data.status, 'disabled');
  assert.equal(data.deleted_at, null);
});

test('normalizeUserMemoryWrite supplies deleted_at for deleted memories', () => {
  const data: Record<string, unknown> = { status: 'deleted' };

  normalizeUserMemoryWrite(data);

  assert.equal(data.status, 'deleted');
  assert.equal(typeof data.deleted_at, 'string');
});

test('normalizeUserMemoryWrite leaves partial patches from reactivating deleted rows', () => {
  const data: Record<string, unknown> = { content: 'updated', deleted_at: '2026-01-01T00:00:00Z' };

  normalizeUserMemoryWrite(data);

  assert.deepEqual(data, { content: 'updated' });
});

test('softDeleteUserMemory updates the row instead of hard deleting', async () => {
  const calls: Array<{ sql: string; params: unknown[] }> = [];
  const client = {
    async query(sql: string, params: unknown[]) {
      calls.push({ sql, params });
      return { rowCount: 1, rows: [] };
    },
  };

  const applied = await softDeleteUserMemory(client, 'owner-1', 'memory-1');

  assert.equal(applied, true);
  assert.equal(calls.length, 1);
  assert.match(calls[0].sql, /UPDATE public\.user_memories/);
  assert.doesNotMatch(calls[0].sql, /DELETE FROM/);
  assert.deepEqual(calls[0].params, ['memory-1', 'owner-1']);
});
