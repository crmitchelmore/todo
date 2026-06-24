import { test } from 'node:test';
import assert from 'node:assert/strict';

import { decideAgentProposal, proposalMeta } from './proposals.ts';

class MemoryStorage {
  private values = new Map<string, string>();
  getItem(key: string) { return this.values.get(key) ?? null; }
  setItem(key: string, value: string) { this.values.set(key, value); }
  removeItem(key: string) { this.values.delete(key); }
}

test('proposalMeta reads action metadata from payload and provenance', () => {
  const meta = proposalMeta({
    proposal_type: 'action',
    payload: JSON.stringify({
      action_type: 'send_email',
      risk_level: 'high',
      autonomy_reason: 'external state mutation',
      thread_id: 'thread-1',
      question: 'What should the agent optimise for?',
      options: [{ id: 'speed', label: 'Speed', value: 'Optimise for speed' }],
      allow_free_text: true,
    }),
    provenance: JSON.stringify({ risk_level: 'medium' }),
  });

  assert.deepEqual(meta, {
    actionType: 'send_email',
    riskLevel: 'high',
    reason: 'external state mutation',
    threadId: 'thread-1',
    question: 'What should the agent optimise for?',
    options: [{ id: 'speed', label: 'Speed', value: 'Optimise for speed' }],
    allowFreeText: true,
  });
});

test('decideAgentProposal posts an authenticated decision', async () => {
  globalThis.localStorage = new MemoryStorage() as Storage;
  globalThis.localStorage.setItem('capture.session', JSON.stringify({ token: 'session-token', userId: 'user-1' }));
  let request: Request | null = null;
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    request = new Request(input, init);
    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  }) as typeof fetch;

  await decideAgentProposal('11111111-1111-4111-8111-111111111111', 'accepted', {
    selected_option: { id: 'speed', label: 'Speed', value: 'Optimise for speed' },
    free_text: '',
  });

  assert.ok(request);
  assert.equal(request.method, 'POST');
  assert.equal(request.headers.get('authorization'), 'Bearer session-token');
  assert.equal(request.headers.get('content-type'), 'application/json');
  const body = await request.json();
  assert.equal(body.decision, 'accepted');
  assert.equal(body.resume_payload.selected_option.id, 'speed');
});
