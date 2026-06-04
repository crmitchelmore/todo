import {
  CompletionSignal,
  ExtractedTodo,
  TaskForCompletionDetection,
} from "./types.js";

export interface ParsedGmailEmail {
  readonly messageId?: string;
  readonly threadId?: string;
  readonly inReplyTo?: string;
  readonly subject?: string;
  readonly text?: string;
  readonly html?: string;
  readonly date?: Date;
  readonly fromAddress?: { readonly name?: string; readonly address: string };
  readonly labels?: readonly string[];
}

const ACTION_PREFIXES: readonly RegExp[] = [
  /^(?:re:\s*)?(?:fwd?:\s*)?(?:action required|todo|to-do|reminder)\s*:?\s*/i,
  /^(?:please|pls)\s+/i,
  /^(?:could|can|would)\s+you\s+/i,
  /^(?:i|we)\s+need\s+(?:you\s+)?to\s+/i,
  /^need\s+(?:you\s+)?to\s+/i,
  /^(?:make sure|remember|don't forget)\s+to\s+/i,
  /^(?:let's|we should|we need to)\s+/i,
];

const ACTION_MARKERS: readonly RegExp[] = [
  /\b(?:action required|todo|to-do|reminder)\s*:/i,
  /\b(?:please|pls)\s+\w+/i,
  /\b(?:could|can|would)\s+you\s+\w+/i,
  /\b(?:i|we)\s+need\s+(?:you\s+)?to\s+\w+/i,
  /\bneed\s+(?:you\s+)?to\s+\w+/i,
  /\b(?:make sure|remember|don't forget)\s+to\s+\w+/i,
  /\b(?:let's|we should|we need to)\s+\w+/i,
];

const DUE_HINTS: ReadonlyArray<[RegExp, string]> = [
  [/\btoday\b/i, "today"],
  [/\btomorrow\b/i, "tomorrow"],
  [/\bend of (the )?week\b/i, "end of week"],
  [/\bnext week\b/i, "next week"],
  [/\bby (mon|tue|wed|thu|fri|sat|sun)/i, "this week"],
];

const COMPLETION_MARKERS: readonly RegExp[] = [
  /\b(?:done|completed|finished|shipped|merged|resolved|closed|sent|paid)\b/i,
  /\bi(?:'ve| have)\s+(?:sent|finished|completed|shipped|merged|resolved|paid)\b/i,
  /\bthis\s+is\s+(?:done|complete|resolved|closed)\b/i,
  /\bno\s+further\s+action\s+(?:needed|required)\b/i,
];

const COMPLETION_LABELS = /\b(?:done|completed|complete|finished|shipped|merged|resolved|closed|sent|paid)\b/i;

export function buildExtractedTodoFromEmail(
  parsed: ParsedGmailEmail,
  uid: number,
  fallbackLabel: string,
): ExtractedTodo | null {
  const subject = cleanWhitespace(parsed.subject ?? "");
  const body = gmailBodyText(parsed.text, parsed.html);
  const candidate = findActionCandidate(subject, body);
  if (!candidate) return null;

  const dueHint = detectDueHint(`${subject} ${body}`);
  const labels = parsed.labels && parsed.labels.length > 0 ? parsed.labels : [fallbackLabel];
  const confidence = scoreActionCandidate(candidate.fromSubject, dueHint, labels);

  return {
    source: "gmail",
    sourceMessageId: parsed.messageId ?? `uid:${uid}`,
    threadId: parsed.threadId ?? parsed.inReplyTo,
    title: candidate.title,
    sourceQuote: candidate.quote,
    confidence,
    sender: parsed.fromAddress,
    receivedAt: parsed.date?.toISOString(),
    dueHint,
    labels,
  };
}

export function buildCompletionSignalsFromEmail(
  parsed: ParsedGmailEmail,
  uid: number,
  tasks: readonly TaskForCompletionDetection[],
): readonly CompletionSignal[] {
  if (tasks.length === 0) return [];
  const subject = cleanWhitespace(parsed.subject ?? "");
  const body = gmailBodyText(parsed.text, parsed.html);
  const labels = parsed.labels ?? [];
  const completion = completionEvidence(subject, body, labels);
  if (!completion) return [];

  const haystack = `${subject} ${body} ${labels.join(" ")}`.toLowerCase();
  const sourceQuote = firstSentence(body) || subject || labels.join(", ");
  return tasks
    .filter((task) => taskMatchesMessage(task, haystack))
    .map((task) => ({
      source: "gmail" as const,
      taskId: task.id,
      messageId: parsed.messageId ?? `uid:${uid}`,
      threadId: parsed.threadId ?? parsed.inReplyTo,
      reason: completion.reason,
      sourceQuote,
      confidence: completion.confidence,
      receivedAt: parsed.date?.toISOString(),
    }));
}

export function gmailBodyText(text?: string, html?: string): string {
  if (text && text.trim().length > 0) return cleanWhitespace(text);
  if (html) return cleanWhitespace(html.replace(/<[^>]+>/g, " "));
  return "";
}

export function firstSentence(text: string): string {
  const clean = cleanWhitespace(text);
  if (clean.length === 0) return "";
  const end = clean.search(/[.!?]\s/);
  const slice = end > 0 ? clean.slice(0, end + 1) : clean;
  return truncate(slice, 200);
}

export function detectDueHint(text: string): string | undefined {
  for (const [re, hint] of DUE_HINTS) {
    if (re.test(text)) return hint;
  }
  return undefined;
}

interface ActionCandidate {
  readonly quote: string;
  readonly title: string;
  readonly fromSubject: boolean;
}

function findActionCandidate(subject: string, body: string): ActionCandidate | null {
  const chunks = [
    ...candidateChunks(subject).map((quote) => ({ quote, fromSubject: true })),
    ...candidateChunks(body).map((quote) => ({ quote, fromSubject: false })),
  ];

  for (const chunk of chunks) {
    if (!looksActionable(chunk.quote)) continue;
    const title = titleFromAction(chunk.quote);
    if (title.length === 0) continue;
    return { quote: truncate(chunk.quote, 240), title, fromSubject: chunk.fromSubject };
  }
  return null;
}

function candidateChunks(text: string): readonly string[] {
  return text
    .split(/\n+|(?<=[.!?])\s+/)
    .map(cleanWhitespace)
    .filter((chunk) => chunk.length > 0);
}

function looksActionable(text: string): boolean {
  return ACTION_MARKERS.some((marker) => marker.test(text));
}

function titleFromAction(text: string): string {
  let title = cleanWhitespace(text);
  const actionStart = firstActionMarkerIndex(title);
  if (actionStart > 0) {
    title = title.slice(actionStart);
  }
  for (const prefix of ACTION_PREFIXES) {
    title = title.replace(prefix, "");
  }
  title = title.replace(/[.!?]+$/g, "");
  title = title.replace(/\b(?:thanks|thank you)\b.*$/i, "");
  title = cleanWhitespace(title);
  if (title.length === 0) return "";
  return truncate(capitalise(title), 120);
}

function firstActionMarkerIndex(text: string): number {
  const indexes = ACTION_MARKERS
    .map((marker) => marker.exec(text)?.index)
    .filter((index): index is number => typeof index === "number");
  return indexes.length === 0 ? 0 : Math.min(...indexes);
}

function scoreActionCandidate(fromSubject: boolean, dueHint: string | undefined, labels: readonly string[]): number {
  const labelBoost = labels.some((label) => /important|starred|inbox/i.test(label)) ? 0.05 : 0;
  const dueBoost = dueHint ? 0.06 : 0;
  const base = fromSubject ? 0.74 : 0.68;
  return Math.min(0.92, Number((base + dueBoost + labelBoost).toFixed(2)));
}

function completionEvidence(
  subject: string,
  body: string,
  labels: readonly string[],
): { readonly reason: string; readonly confidence: number } | null {
  const text = `${subject} ${body}`;
  const hasPhrase = COMPLETION_MARKERS.some((marker) => marker.test(text));
  const completionLabel = labels.find((label) => COMPLETION_LABELS.test(label));
  if (!hasPhrase && !completionLabel) return null;

  if (hasPhrase && completionLabel) {
    return {
      reason: `Recent email mentions completion and carries Gmail label "${completionLabel}".`,
      confidence: 0.84,
    };
  }
  if (completionLabel) {
    return {
      reason: `Gmail label "${completionLabel}" suggests this task is complete.`,
      confidence: 0.72,
    };
  }
  return {
    reason: "Recent email mentions this task with a completion phrase.",
    confidence: 0.7,
  };
}

function taskMatchesMessage(task: TaskForCompletionDetection, haystack: string): boolean {
  const text = `${task.title} ${task.context ?? ""}`;
  const tokens = text
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((token) => token.length > 3);
  if (tokens.length === 0) return false;
  const hits = tokens.filter((token) => haystack.includes(token)).length;
  return hits / tokens.length >= 0.6;
}

function cleanWhitespace(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}

function capitalise(value: string): string {
  return value.charAt(0).toUpperCase() + value.slice(1);
}

function truncate(value: string, max: number): string {
  return value.length > max ? `${value.slice(0, max - 3)}...` : value;
}
