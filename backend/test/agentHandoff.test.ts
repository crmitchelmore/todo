import assert from 'node:assert/strict';
import { test } from 'node:test';
import { agentHandoffRequestId, parseAgentHandoffInput } from '../src/agentHandoff.js';

test('parseAgentHandoffInput accepts bounded research and attempt requests', () => {
  assert.deepEqual(parseAgentHandoffInput({ mode: 'research', instructions: '  compare options  ' }), {
    mode: 'research',
    instructions: 'compare options',
  });
  assert.deepEqual(parseAgentHandoffInput({ mode: 'attempt' }), {
    mode: 'attempt',
    instructions: null,
  });
});

test('parseAgentHandoffInput rejects unknown modes and caps instructions', () => {
  assert.equal(parseAgentHandoffInput({ mode: 'delete_everything' }), null);
  const parsed = parseAgentHandoffInput({ mode: 'research', instructions: 'x'.repeat(1200) });
  assert.equal(parsed?.instructions?.length, 1000);
});

test('agentHandoffRequestId collapses rapid duplicate requests but permits later iterations', () => {
  const base = {
    ownerId: 'owner-1',
    taskId: 'task-1',
    mode: 'research' as const,
    instructions: 'look deeper',
  };
  const first = agentHandoffRequestId({ ...base, now: new Date('2026-06-04T21:00:00Z') });
  const retry = agentHandoffRequestId({ ...base, now: new Date('2026-06-04T21:00:10Z') });
  const later = agentHandoffRequestId({ ...base, now: new Date('2026-06-04T21:00:45Z') });
  assert.equal(first, retry);
  assert.notEqual(first, later);
});
