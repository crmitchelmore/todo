import assert from 'node:assert/strict';
import test from 'node:test';

import { enrichDeterministic } from './enrich.js';
import { learnCategoryHints } from './historyLearning.js';

/**
 * Behaviour tests for the auto-organisation pass. These assert observable outcomes a user
 * cares about — "this looks like an engineering task", "a due date was understood" — not the
 * internal scoring, so they stay green across refactors of the heuristics.
 */

const NOW = new Date('2026-06-02T09:00:00.000Z'); // a Tuesday

test('classifies the owner\'s real personas', () => {
  const cases: ReadonlyArray<[string, string]> = [
    ['Review the auth service PR before we deploy', 'engineering'],
    ['Prep talking points for my 1:1 with Sarah', 'leadership'],
    ['Take the bins out and do the laundry', 'home'],
    ['Repair the kitchen sink tap', 'home'],
    ['Buy milk and pick up a parcel from the post office', 'errands'],
    ['Book a dentist appointment', 'health'],
    ['Pay the council tax bill', 'finance'],
    ['Call mum for her birthday', 'personal'],
  ];
  for (const [title, expected] of cases) {
    assert.equal(enrichDeterministic(title, NOW).suggestedCategory, expected, title);
  }
});

test('understands a due date from natural language', () => {
  const withDate = enrichDeterministic('Submit the board report by Friday', NOW);
  assert.notEqual(withDate.suggestedDueAt, null);
  // Forward-dated: the suggested date is in the future relative to capture time.
  assert.ok(new Date(withDate.suggestedDueAt as string).getTime() > NOW.getTime());
});

test('leaves no-signal captures unclassified rather than guessing', () => {
  const noise = enrichDeterministic('zxcvbnm qwerty', NOW);
  assert.equal(noise.suggestedCategory, null);
  assert.equal(noise.suggestedDueAt, null);
  assert.equal(noise.confidence, 0);
});

test('is more confident when it has more signal', () => {
  const vague = enrichDeterministic('think about stuff', NOW);
  const rich = enrichDeterministic('URGENT: fix the deploy bug by tomorrow', NOW);
  assert.ok(rich.confidence > vague.confidence);
  assert.ok(rich.confidence <= 1);
});

test('never decides final structure — it only proposes (status is a human decision)', () => {
  const e = enrichDeterministic('ship the release today', NOW);
  assert.equal(e.source, 'server');
  assert.equal('status' in e, false);
  assert.equal(e.suggestedPriority, 1);
});

test('detects lightweight recurrence and proposal tags', () => {
  const e = enrichDeterministic('Pay the rent every month', NOW);
  assert.equal(e.recurrence, 'monthly');
  assert.deepEqual(e.suggestedTags, ['monthly']);
});

test('learns category hints from confirmed history without overriding stronger built-ins', () => {
  const hints = learnCategoryHints([
    { title: 'Book football practice with coach', category: 'personal' },
    { title: 'Pack football kit for Saturday', category: 'personal' },
    { title: 'Renew hosting certificate', category: 'engineering' },
  ]);

  assert.equal(enrichDeterministic('sort football boots', NOW, hints).suggestedCategory, 'personal');
  assert.equal(enrichDeterministic('deploy football stats service', NOW, hints).suggestedCategory, 'engineering');
});
