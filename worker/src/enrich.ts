import * as chrono from 'chrono-node';
import type { CategoryHints } from './historyLearning.js';

/**
 * Server-side enrichment. Richer than the on-device suggester (which is deliberately cheap so it
 * never delays capture). Runs in the background and only fills the suggestion_* fields — it never
 * decides the final structure. The human still confirms before anything becomes a real todo.
 */

export interface Enrichment {
  suggestedDueAt: string | null; // ISO-8601
  suggestedCategory: string | null;
  suggestedPriority: number | null; // 0 highest .. 4 lowest, still only a proposal.
  suggestedTags: string[];
  recurrence: string | null;
  confidence: number; // 0..1
  source: 'server' | 'llm';
}

export interface CategorisationRule {
  title: string;
  instructions: string;
  category: string | null;
  tags: string[];
}

// Broader keyword sets than the client; the server can afford a little more work.
const CATEGORY_KEYWORDS: Record<string, string[]> = {
  engineering: ['pr', 'pull request', 'merge', 'code review', 'review', 'deploy', 'deployment',
    'release', 'ship', 'bug', 'debug', 'incident', 'on-call', 'oncall', 'pager', 'alert',
    'architecture', 'design doc', 'tech spec', 'spec', 'rfc', 'refactor', 'test', 'tests', 'ci',
    'cd', 'pipeline', 'build', 'infra', 'infrastructure', 'terraform', 'kubernetes', 'docker',
    'api', 'backend', 'frontend', 'database', 'migration', 'jira', 'ticket', 'issue', 'slack',
    'github', 'branch', 'commit', 'repo', 'monitoring', 'logs', 'sentry', 'railway'],
  leadership: ['1:1', 'one-on-one', 'one to one', 'performance review', 'review cycle', 'hiring',
    'hire', 'interview', 'candidate', 'recruiting', 'strategy', 'roadmap', 'planning', 'plan',
    'quarterly', 'okr', 'okrs', 'goal', 'goals', 'team sync', 'standup', 'retro', 'retrospective',
    'stakeholder', 'management update', 'exec update', 'leadership', 'mentor', 'mentoring',
    'coaching', 'feedback', 'promotion', 'career', 'headcount', 'budget review'],
  home: ['clean', 'fix', 'laundry', 'cook', 'tidy', 'bin', 'bins', 'rubbish', 'trash',
    'water plants', 'vacuum', 'repair', 'assemble', 'declutter', 'garden', 'lawn', 'mow',
    'diy', 'paint', 'plumber', 'electrician', 'sink', 'tap', 'boiler', 'door', 'kids', 'school run',
    'family', 'meal prep'],
  errands: ['buy', 'pick up', 'pickup', 'grocery', 'groceries', 'shop', 'shopping', 'post office',
    'pharmacy', 'return', 'collect', 'order', 'drop off', 'parcel', 'package', 'chemist',
    'dry cleaning', 'appointment to run', 'book appointment', 'car wash'],
  health: ['gym', 'run', 'doctor', 'dentist', 'workout', 'meds', 'medicine', 'appointment',
    'physio', 'therapy', 'prescription', 'walk', 'yoga', 'optician', 'checkup', 'blood test',
    'vaccine', 'vaccination', 'health'],
  finance: ['pay', 'bill', 'tax', 'bank', 'transfer', 'budget', 'renew', 'renewal', 'subscription',
    'mortgage', 'rent', 'insurance', 'refund', 'invoice', 'expense', 'expenses', 'pension',
    'savings', 'accountant', 'hmrc', 'vat'],
  personal: ['call', 'text', 'birthday', 'dinner', 'meet', 'party', 'rsvp', 'message', 'catch up',
    'visit', 'wedding', 'reunion', 'friend', 'friends', 'mum', 'dad', 'parents', 'coffee',
    'date night', 'holiday', 'travel']
};

// Phrases that hint urgency; used only to bump confidence (priority stays a human decision).
const URGENCY_HINTS = ['urgent', 'asap', 'today', 'now', 'immediately', 'deadline', 'eod', 'cob'];
const RECURRENCE_HINTS: ReadonlyArray<[string, string[]]> = [
  ['daily', ['every day', 'daily', 'each day']],
  ['weekly', ['every week', 'weekly', 'each week']],
  ['monthly', ['every month', 'monthly', 'each month']],
  ['yearly', ['every year', 'yearly', 'annually', 'annual']]
];

/**
 * Match a keyword/phrase on token boundaries so `pr` doesn't fire on "prep" and `run` doesn't
 * fire on "running errand". Boundaries are any non-alphanumeric char (or string ends), which also
 * lets phrases like `1:1`, `on-call` and `code review` match naturally. Compiled once per keyword.
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

const URGENCY_MATCHERS = URGENCY_HINTS.map(boundedMatcher);
const RECURRENCE_MATCHERS = RECURRENCE_HINTS.map(([label, hints]) => ({
  label,
  patterns: hints.map(boundedMatcher),
}));
let llmDisabledReason: string | null = null;
const STOP_WORDS = new Set([
  'the', 'and', 'for', 'this', 'that', 'with', 'from', 'you', 'are', 'not', 'but',
  'all', 'any', 'can', 'get', 'has', 'had', 'was', 'were', 'his', 'her', 'its',
  'our', 'out', 'who', 'how', 'why', 'one', 'two', 'new', 'use', 'she', 'him',
  'they', 'them', 'their', 'there', 'these', 'than', 'then', 'also', 'some',
  'into', 'other', 'about', 'after', 'been', 'when', 'where', 'which', 'would',
  'could', 'should', 'will', 'your', 'only', 'very', 'just', 'more', 'most',
  'such', 'even', 'over', 'back', 'down', 'well'
]);

function normalizeTags(tags: unknown): string[] {
  if (!Array.isArray(tags)) return [];
  const out: string[] = [];
  for (const tag of tags) {
    if (typeof tag !== 'string') continue;
    const normalized = tag.trim().toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/^-+|-+$/g, '');
    if (normalized.length >= 2 && normalized.length <= 32 && !out.includes(normalized)) out.push(normalized);
    if (out.length >= 6) break;
  }
  return out;
}

function titleTokens(text: string): Set<string> {
  return new Set(
    text
      .toLowerCase()
      .split(/[^\p{L}\p{N}]+/u)
      .map((token) => token.trim())
      .filter((token) => token.length >= 3 && !STOP_WORDS.has(token))
  );
}

function ruleScore(title: string, rule: CategorisationRule): number {
  const titleSet = titleTokens(title);
  if (titleSet.size === 0) return 0;
  const ruleTokens = titleTokens(`${rule.title} ${rule.instructions}`);
  let matches = 0;
  for (const token of ruleTokens) if (titleSet.has(token)) matches += 1;
  return matches;
}

function recurrenceFor(title: string): string | null {
  for (const { label, patterns } of RECURRENCE_MATCHERS) {
    if (patterns.some((re) => re.test(title))) return label;
  }
  return null;
}

export function enrichDeterministic(
  title: string,
  now = new Date(),
  historyHints: CategoryHints = {},
  rules: readonly CategorisationRule[] = []
): Enrichment {
  let suggestedDueAt: string | null = null;
  const parsed = chrono.parse(title, now, { forwardDate: true });
  if (parsed.length > 0) suggestedDueAt = parsed[0].date().toISOString();

  let suggestedCategory: string | null = null;
  let best = 0;
  for (const { category, patterns } of CATEGORY_MATCHERS) {
    const builtInHits = patterns.reduce((n, re) => (re.test(title) ? n + 1 : n), 0);
    const learnedHits = (historyHints[category] ?? [])
      .map(boundedMatcher)
      .reduce((n, re) => (re.test(title) ? n + 1 : n), 0);
    const score = builtInHits + learnedHits * 0.75;
    if (score > best) {
      best = score;
      suggestedCategory = category;
    }
  }
  const ruleTags: string[] = [];
  for (const rule of rules) {
    const score = ruleScore(title, rule);
    if (score <= 0) continue;
    if (rule.category && score + 0.5 > best) {
      best = score + 0.5;
      suggestedCategory = rule.category;
    }
    ruleTags.push(...rule.tags);
  }

  const urgent = URGENCY_MATCHERS.some((re) => re.test(title));
  const recurrence = recurrenceFor(title);
  const suggestedPriority = urgent ? 1 : null;
  const suggestedTags = normalizeTags([
    urgent ? 'urgent' : null,
    recurrence,
    ...ruleTags,
  ].filter(Boolean));
  const confidence = Math.min(
    1,
    (suggestedDueAt ? 0.55 : 0) + best * 0.2 + (urgent ? 0.15 : 0) + (recurrence ? 0.1 : 0)
  );

  return {
    suggestedDueAt,
    suggestedCategory,
    suggestedPriority,
    suggestedTags,
    recurrence,
    confidence,
    source: 'server',
  };
}

/**
 * Optional LLM upgrade. Only used when an API key is configured; otherwise we stay fully
 * deterministic and offline. Falls back to the deterministic result on any error.
 */
export async function enrich(
  title: string,
  now = new Date(),
  historyHints: CategoryHints = {},
  rules: readonly CategorisationRule[] = []
): Promise<Enrichment> {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey || llmDisabledReason) return enrichDeterministic(title, now, historyHints, rules);

  try {
    const model = process.env.ENRICH_LLM_MODEL ?? 'gpt-4o-mini';
    const baseUrl = (process.env.OPENAI_BASE_URL ?? 'https://api.openai.com/v1').replace(/\/$/, '');
    const categories = [...new Set([
      ...Object.keys(CATEGORY_KEYWORDS),
      ...rules.map((rule) => rule.category).filter((category): category is string => Boolean(category))
    ])];
    const hintSummary = Object.entries(historyHints)
      .filter(([, hints]) => hints.length > 0)
      .map(([category, hints]) => `${category}: ${hints.slice(0, 12).join(', ')}`)
      .join('; ');
    const sys =
      `You organise todo items. Given a raw capture, return strict JSON: ` +
      `{"category": one of ${JSON.stringify(categories)} or null, ` +
      `"due_at": an ISO-8601 datetime or null, "priority": 0..4 or null, ` +
      `"tags": an array of up to 6 short lowercase labels, "recurrence": a short rule like ` +
      `"daily", "weekly", "monthly" or null, "confidence": 0..1}. ` +
      `Current time is ${now.toISOString()}. Resolve relative dates against it. ` +
      (hintSummary ? `The user's confirmed-history category hints are: ${hintSummary}. ` : '') +
      (rules.length > 0
        ? `The user's explicit categorisation rules are: ${rules.slice(0, 20).map((rule) =>
          `${rule.title}: ${rule.instructions}${rule.category ? ` -> category ${rule.category}` : ''}${rule.tags.length ? `, tags ${rule.tags.join(', ')}` : ''}`
        ).join(' | ')}. `
        : '') +
      `Only JSON.`;

    const resp = await fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${apiKey}` },
      body: JSON.stringify({
        model,
        temperature: 0,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: sys },
          { role: 'user', content: title }
        ]
      })
    });
    if (!resp.ok) {
      if (resp.status === 401 || resp.status === 403) {
        llmDisabledReason = `LLM HTTP ${resp.status}`;
      }
      throw new Error(`LLM HTTP ${resp.status}`);
    }
    const json: any = await resp.json();
    const content = json.choices?.[0]?.message?.content;
    const out = JSON.parse(content);
    const cat = typeof out.category === 'string' && categories.includes(out.category)
      ? out.category
      : null;
    let due: string | null = null;
    if (typeof out.due_at === 'string') {
      const d = new Date(out.due_at);
      if (!Number.isNaN(d.getTime())) due = d.toISOString();
    }
    const conf = typeof out.confidence === 'number' ? Math.max(0, Math.min(1, out.confidence)) : 0.5;
    const priority = Number.isInteger(out.priority) && out.priority >= 0 && out.priority <= 4
      ? out.priority
      : null;
    const recurrence = typeof out.recurrence === 'string' && out.recurrence.trim().length > 0
      ? out.recurrence.trim().slice(0, 80)
      : null;
    return {
      suggestedDueAt: due,
      suggestedCategory: cat,
      suggestedPriority: priority,
      suggestedTags: normalizeTags(out.tags),
      recurrence,
      confidence: conf,
      source: 'llm',
    };
  } catch (err) {
    console.warn('[worker] LLM enrichment failed, falling back to deterministic:', String(err));
    return enrichDeterministic(title, now, historyHints, rules);
  }
}
