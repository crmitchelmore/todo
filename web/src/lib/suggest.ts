import * as chrono from 'chrono-node';

// Lightweight, fully on-device category guesser. Deliberately cheap so it never delays capture.
const CATEGORY_KEYWORDS: Record<string, string[]> = {
  engineering: ['pr', 'pull request', 'code review', 'review', 'deploy', 'bug', 'incident', 'on-call', 'architecture', 'spec', 'refactor', 'test', 'ci', 'build', 'infra', 'api', 'jira'],
  leadership: ['1:1', 'one-on-one', 'performance review', 'hiring', 'interview', 'strategy', 'roadmap', 'planning', 'okr', 'team sync', 'standup', 'retro', 'stakeholder', 'mentor'],
  home: ['clean', 'fix', 'laundry', 'cook', 'tidy', 'bin', 'water plants', 'repair', 'garden', 'kids', 'family'],
  errands: ['buy', 'pick up', 'grocery', 'shop', 'post office', 'pharmacy', 'return', 'collect', 'drop off'],
  health: ['gym', 'run', 'doctor', 'dentist', 'workout', 'meds', 'appointment', 'physio'],
  finance: ['pay', 'bill', 'tax', 'bank', 'transfer', 'budget', 'renew', 'subscription'],
  personal: ['call', 'text', 'birthday', 'dinner', 'meet', 'party', 'rsvp', 'friend', 'mum', 'dad']
};

export interface Suggestion {
  dueAt: string | null; // ISO-8601
  category: string | null;
  confidence: number; // 0..1
}

/**
 * Match a keyword on token boundaries so `pr` doesn't fire on "prep" and `run` doesn't fire on
 * "running". Boundaries are non-alphanumeric chars or string ends, which also lets `1:1`,
 * `on-call` and `code review` match. Compiled once per keyword.
 */
function boundedMatcher(keyword: string): RegExp {
  const escaped = keyword.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`(^|[^a-z0-9])${escaped}([^a-z0-9]|$)`, 'i');
}

const CATEGORY_MATCHERS: ReadonlyArray<{ category: string; patterns: readonly RegExp[] }> =
  Object.entries(CATEGORY_KEYWORDS).map(([category, words]) => ({
    category,
    patterns: words.map(boundedMatcher),
  }));

export function suggest(text: string, now = new Date()): Suggestion {
  let dueAt: string | null = null;
  const parsed = chrono.parse(text, now, { forwardDate: true });
  if (parsed.length > 0) dueAt = parsed[0].date().toISOString();

  let category: string | null = null;
  let best = 0;
  for (const { category: cat, patterns } of CATEGORY_MATCHERS) {
    const hits = patterns.reduce((n, re) => (re.test(text) ? n + 1 : n), 0);
    if (hits > best) {
      best = hits;
      category = cat;
    }
  }

  const confidence = Math.min(1, (dueAt ? 0.5 : 0) + best * 0.25);
  return { dueAt, category, confidence };
}
