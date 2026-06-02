import assert from 'node:assert/strict';
import test from 'node:test';

import { suggest } from './suggest';

/**
 * The instant, on-device suggester runs on every keystroke-to-capture, so these tests pin the
 * behaviour users feel: fast classification of their real task types and natural-language dates.
 * They assert outcomes, not scoring internals, so they survive heuristic refactors.
 */

const NOW = new Date('2026-06-02T09:00:00.000Z');

test('classifies common task types on word boundaries (no false "pr" in "prep")', () => {
  assert.equal(suggest('Prep for the 1:1 with my report', NOW).category, 'leadership');
  assert.equal(suggest('Review the PR and deploy', NOW).category, 'engineering');
  assert.equal(suggest('Do the laundry', NOW).category, 'home');
  assert.equal(suggest('Book a doctor appointment', NOW).category, 'health');
});

test('extracts a forward-dated due date from natural language', () => {
  const s = suggest('Call the bank tomorrow', NOW);
  assert.notEqual(s.dueAt, null);
  assert.ok(new Date(s.dueAt as string).getTime() > NOW.getTime());
});

test('stays neutral on ambiguous input', () => {
  const s = suggest('hmm', NOW);
  assert.equal(s.category, null);
  assert.equal(s.dueAt, null);
  assert.equal(s.confidence, 0);
});
