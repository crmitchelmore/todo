import * as chrono from 'chrono-node';

/**
 * Server-side enrichment. Richer than the on-device suggester (which is deliberately cheap so it
 * never delays capture). Runs in the background and only fills the suggestion_* fields — it never
 * decides the final structure. The human still confirms before anything becomes a real todo.
 */

export interface Enrichment {
  suggestedDueAt: string | null; // ISO-8601
  suggestedCategory: string | null;
  confidence: number; // 0..1
  source: 'server' | 'llm';
}

// Broader keyword sets than the client; the server can afford a little more work.
const CATEGORY_KEYWORDS: Record<string, string[]> = {
  work: ['email', 'meeting', 'report', 'deck', 'client', 'invoice', 'slack', 'jira', 'pr',
    'deploy', 'standup', 'review', 'ticket', 'spec', 'proposal', 'presentation', 'demo', 'sync'],
  errands: ['buy', 'pick up', 'grocery', 'shop', 'post office', 'pharmacy', 'return', 'collect',
    'order', 'drop off', 'parcel', 'package'],
  health: ['gym', 'run', 'doctor', 'dentist', 'workout', 'meds', 'appointment', 'physio',
    'therapy', 'prescription', 'walk', 'yoga'],
  finance: ['pay', 'bill', 'tax', 'bank', 'transfer', 'budget', 'renew', 'subscription',
    'mortgage', 'rent', 'insurance', 'refund'],
  home: ['clean', 'fix', 'laundry', 'cook', 'tidy', 'bin', 'water plants', 'vacuum', 'repair',
    'assemble', 'declutter', 'garden'],
  social: ['call', 'text', 'birthday', 'dinner', 'meet', 'party', 'rsvp', 'message', 'catch up',
    'visit', 'wedding', 'reunion']
};

// Phrases that hint urgency; used only to bump confidence (priority stays a human decision).
const URGENCY_HINTS = ['urgent', 'asap', 'today', 'now', 'immediately', 'deadline', 'eod', 'cob'];

export function enrichDeterministic(title: string, now = new Date()): Enrichment {
  const lower = title.toLowerCase();

  let suggestedDueAt: string | null = null;
  const parsed = chrono.parse(title, now, { forwardDate: true });
  if (parsed.length > 0) suggestedDueAt = parsed[0].date().toISOString();

  let suggestedCategory: string | null = null;
  let best = 0;
  for (const [cat, words] of Object.entries(CATEGORY_KEYWORDS)) {
    const hits = words.filter((w) => lower.includes(w)).length;
    if (hits > best) {
      best = hits;
      suggestedCategory = cat;
    }
  }

  const urgent = URGENCY_HINTS.some((h) => lower.includes(h));
  const confidence = Math.min(
    1,
    (suggestedDueAt ? 0.55 : 0) + best * 0.2 + (urgent ? 0.15 : 0)
  );

  return { suggestedDueAt, suggestedCategory, confidence, source: 'server' };
}

/**
 * Optional LLM upgrade. Only used when an API key is configured; otherwise we stay fully
 * deterministic and offline. Falls back to the deterministic result on any error.
 */
export async function enrich(title: string, now = new Date()): Promise<Enrichment> {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) return enrichDeterministic(title, now);

  try {
    const model = process.env.ENRICH_LLM_MODEL ?? 'gpt-4o-mini';
    const categories = Object.keys(CATEGORY_KEYWORDS);
    const sys =
      `You organise todo items. Given a raw capture, return strict JSON: ` +
      `{"category": one of ${JSON.stringify(categories)} or null, ` +
      `"due_at": an ISO-8601 datetime or null, "confidence": 0..1}. ` +
      `Current time is ${now.toISOString()}. Resolve relative dates against it. Only JSON.`;

    const resp = await fetch('https://api.openai.com/v1/chat/completions', {
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
    if (!resp.ok) throw new Error(`LLM HTTP ${resp.status}`);
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
    return { suggestedDueAt: due, suggestedCategory: cat, confidence: conf, source: 'llm' };
  } catch (err) {
    console.warn('[worker] LLM enrichment failed, falling back to deterministic:', String(err));
    return enrichDeterministic(title, now);
  }
}
