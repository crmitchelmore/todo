import assert from 'node:assert/strict';
import test from 'node:test';
import { parseAgentHandoffMetadata } from './handoff.js';

const requestId = '4d2fa518-80f4-5dd0-8436-71062feb7532';

test('parseAgentHandoffMetadata reads bounded request metadata', () => {
  assert.deepEqual(parseAgentHandoffMetadata(JSON.stringify({
    request_id: requestId,
    mode: 'attempt',
    instructions: '  gather facts first  ',
  })), {
    requestId,
    mode: 'attempt',
    instructions: 'gather facts first',
  });
});

test('parseAgentHandoffMetadata rejects invalid request metadata', () => {
  assert.equal(parseAgentHandoffMetadata({ request_id: 'bad', mode: 'attempt' }), null);
  assert.equal(parseAgentHandoffMetadata({ request_id: requestId, mode: 'unknown' }), null);
  assert.equal(parseAgentHandoffMetadata('not json'), null);
});
