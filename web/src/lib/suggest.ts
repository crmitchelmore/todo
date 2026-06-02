import * as chrono from 'chrono-node';

// Lightweight, fully on-device category guesser. Deliberately cheap so it never delays capture.
const CATEGORY_KEYWORDS: Record<string, string[]> = {
  work: ['email', 'meeting', 'report', 'deck', 'client', 'invoice', 'slack', 'jira', 'pr', 'deploy', 'standup'],
  errands: ['buy', 'pick up', 'grocery', 'shop', 'post office', 'pharmacy', 'return', 'collect'],
  health: ['gym', 'run', 'doctor', 'dentist', 'workout', 'meds', 'appointment'],
  finance: ['pay', 'bill', 'tax', 'bank', 'transfer', 'budget', 'renew'],
  home: ['clean', 'fix', 'laundry', 'cook', 'tidy', 'bin', 'water plants'],
  social: ['call', 'text', 'birthday', 'dinner', 'meet', 'party', 'rsvp']
};

export interface Suggestion {
  dueAt: string | null; // ISO-8601
  category: string | null;
  confidence: number; // 0..1
}

export function suggest(text: string, now = new Date()): Suggestion {
  const lower = text.toLowerCase();

  let dueAt: string | null = null;
  const parsed = chrono.parse(text, now, { forwardDate: true });
  if (parsed.length > 0) dueAt = parsed[0].date().toISOString();

  let category: string | null = null;
  let best = 0;
  for (const [cat, words] of Object.entries(CATEGORY_KEYWORDS)) {
    const hits = words.filter((w) => lower.includes(w)).length;
    if (hits > best) {
      best = hits;
      category = cat;
    }
  }

  const confidence = Math.min(1, (dueAt ? 0.5 : 0) + best * 0.25);
  return { dueAt, category, confidence };
}
