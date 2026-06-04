import assert from 'node:assert/strict';
import test from 'node:test';
import type pg from 'pg';

import { classifyActionRisk, deterministicUuid, interruptForHumanDecision } from './hitl.js';

class FakeClient {
  readonly calls: Array<{ sql: string; params: unknown[] }> = [];

  async query(sql: string, params: unknown[] = []): Promise<{ rowCount: number; rows: unknown[] }> {
    this.calls.push({ sql, params });
    return { rowCount: 1, rows: [] };
  }
}

test('classifies read-only context work as low risk', () => {
  assert.equal(classifyActionRisk('web_search'), 'low');
  assert.equal(classifyActionRisk('calendar_read'), 'low');
  assert.equal(classifyActionRisk('send_email'), 'high');
  assert.equal(classifyActionRisk('draft_email'), 'medium');
});

test('low-risk actions do not create a human checkpoint', async () => {
  const client = new FakeClient();
  const result = await interruptForHumanDecision(client as unknown as pg.PoolClient, {
    ownerId: 'owner-1',
    taskId: 'task-1',
    threadId: 'thread-1',
    interruptBefore: 'web_search',
    actionType: 'web_search',
    title: 'Search the web',
    payload: { query: 'capture' },
  });

  assert.equal(result.interrupted, false);
  assert.equal(result.status, 'skipped');
  assert.equal(client.calls.length, 0);
});

test('consequential actions create idempotent proposal and checkpoint rows', async () => {
  const client = new FakeClient();
  const action = {
    ownerId: 'owner-1',
    taskId: 'task-1',
    threadId: 'agent-thread-42',
    checkpointKey: 'before-send-email',
    interruptBefore: 'send_email',
    actionType: 'send_email',
    title: 'Approve sending email',
    body: 'Send a follow-up email only after approval.',
    payload: { to: 'example@example.invalid', subject: 'Follow-up' },
    source: 'openclaw',
    confidence: 0.8,
  };

  const result = await interruptForHumanDecision(client as unknown as pg.PoolClient, action);

  assert.equal(result.interrupted, true);
  assert.equal(result.riskLevel, 'high');
  assert.equal(client.calls.length, 2);
  assert.match(client.calls[0].sql, /INSERT INTO public\.agent_proposals/);
  assert.match(client.calls[0].sql, /ON CONFLICT \(id\)/);
  assert.match(client.calls[1].sql, /INSERT INTO public\.agent_checkpoints/);
  assert.match(client.calls[1].sql, /ON CONFLICT \(id\)/);
  assert.equal(result.checkpointId, deterministicUuid('owner-1:agent-thread-42:before-send-email'));
  assert.equal(result.proposalId, deterministicUuid('owner-1:agent-thread-42:before-send-email:proposal'));
});
