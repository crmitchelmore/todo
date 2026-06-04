import assert from 'node:assert/strict';
import test from 'node:test';
import type pg from 'pg';

import {
  applyAgentProposalDecision,
  parseAgentProposalDecision,
  serializeResumePayload,
} from '../src/agentDecision.ts';

class FakeClient {
  readonly calls: Array<{ sql: string; params: unknown[] }> = [];
  constructor(private readonly proposalStatus: string | null = 'pending') {}

  async query(sql: string, params: unknown[] = []): Promise<{ rowCount: number; rows: Array<Record<string, unknown>> }> {
    this.calls.push({ sql, params });
    if (/SELECT id, status/.test(sql)) {
      if (!this.proposalStatus) return { rowCount: 0, rows: [] };
      return { rowCount: 1, rows: [{ id: params[1], status: this.proposalStatus }] };
    }
    return { rowCount: 1, rows: [] };
  }
}

test('parseAgentProposalDecision only accepts explicit terminal decisions', () => {
  assert.equal(parseAgentProposalDecision('accepted'), 'accepted');
  assert.equal(parseAgentProposalDecision('rejected'), 'rejected');
  assert.equal(parseAgentProposalDecision('approve'), null);
  assert.equal(parseAgentProposalDecision(null), null);
});

test('serializeResumePayload validates size before the database constraint', () => {
  assert.equal(serializeResumePayload(undefined), null);
  assert.equal(serializeResumePayload({ resumed_by: 'test' }), '{"resumed_by":"test"}');
  assert.throws(() => serializeResumePayload({ huge: 'x'.repeat(5000) }), /4096 bytes/);
});

test('applyAgentProposalDecision updates proposal and linked checkpoint together', async () => {
  const client = new FakeClient();
  const outcome = await applyAgentProposalDecision(
    client as unknown as pg.PoolClient,
    'owner-1',
    'proposal-1',
    'accepted',
    '{"resumed_by":"test"}'
  );

  assert.equal(outcome, 'decided');
  assert.equal(client.calls.length, 3);
  assert.match(client.calls[0].sql, /FOR UPDATE/);
  assert.match(client.calls[1].sql, /UPDATE public\.agent_proposals/);
  assert.deepEqual(client.calls[1].params, ['owner-1', 'proposal-1', 'accepted']);
  assert.match(client.calls[2].sql, /UPDATE public\.agent_checkpoints/);
  assert.deepEqual(client.calls[2].params, ['owner-1', 'proposal-1', 'approved', '{"resumed_by":"test"}']);
});

test('applyAgentProposalDecision distinguishes missing and already-decided proposals', async () => {
  assert.equal(
    await applyAgentProposalDecision(new FakeClient(null) as unknown as pg.PoolClient, 'owner-1', 'proposal-1', 'rejected', null),
    'not_found'
  );
  assert.equal(
    await applyAgentProposalDecision(new FakeClient('accepted') as unknown as pg.PoolClient, 'owner-1', 'proposal-1', 'rejected', null),
    'not_pending'
  );
});
