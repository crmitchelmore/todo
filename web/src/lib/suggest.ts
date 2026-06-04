import * as chrono from 'chrono-node';

// Lightweight, fully on-device category guesser. Deliberately cheap so it never delays capture.
const CATEGORY_KEYWORDS: Record<string, string[]> = {
  engineering: ['pr', 'pull request', 'merge', 'code review', 'review', 'deploy', 'deployment', 'release', 'ship', 'bug', 'debug', 'incident', 'on-call', 'oncall', 'pager', 'alert', 'architecture', 'design doc', 'tech spec', 'spec', 'rfc', 'refactor', 'test', 'tests', 'ci', 'cd', 'pipeline', 'build', 'infra', 'infrastructure', 'terraform', 'kubernetes', 'docker', 'api', 'backend', 'frontend', 'database', 'migration', 'jira', 'ticket', 'issue', 'slack', 'github', 'branch', 'commit', 'repo', 'monitoring', 'logs', 'sentry', 'railway'],
  leadership: ['1:1', 'one-on-one', 'one to one', 'performance review', 'review cycle', 'hiring', 'hire', 'interview', 'candidate', 'recruiting', 'strategy', 'roadmap', 'planning', 'plan', 'quarterly', 'okr', 'okrs', 'goal', 'goals', 'team sync', 'standup', 'retro', 'retrospective', 'stakeholder', 'management update', 'exec update', 'leadership', 'mentor', 'mentoring', 'coaching', 'feedback', 'promotion', 'career', 'headcount', 'budget review'],
  home: ['clean', 'laundry', 'cook', 'tidy', 'bin', 'bins', 'rubbish', 'trash', 'water plants', 'vacuum', 'repair', 'assemble', 'declutter', 'garden', 'lawn', 'mow', 'diy', 'paint', 'plumber', 'electrician', 'sink', 'tap', 'boiler', 'door', 'kids', 'school run', 'family', 'meal prep'],
  errands: ['buy', 'pick up', 'pickup', 'grocery', 'groceries', 'shop', 'shopping', 'post office', 'pharmacy', 'return', 'collect', 'order', 'drop off', 'parcel', 'package', 'chemist', 'dry cleaning', 'book appointment', 'car wash'],
  health: ['gym', 'run', 'doctor', 'dentist', 'workout', 'meds', 'medicine', 'appointment', 'physio', 'therapy', 'prescription', 'walk', 'yoga', 'optician', 'checkup', 'blood test', 'vaccine', 'vaccination', 'health'],
  finance: ['pay', 'bill', 'tax', 'bank', 'transfer', 'budget', 'renew', 'renewal', 'subscription', 'mortgage', 'rent', 'insurance', 'refund', 'invoice', 'expense', 'expenses', 'pension', 'savings', 'accountant', 'hmrc', 'vat'],
  personal: ['call', 'text', 'birthday', 'dinner', 'meet', 'party', 'rsvp', 'message', 'catch up', 'visit', 'wedding', 'reunion', 'friend', 'friends', 'mum', 'dad', 'parents', 'coffee', 'date night', 'holiday', 'travel']
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
