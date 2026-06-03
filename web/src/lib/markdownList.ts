/**
 * Parses a pasted markdown / checkbox list into individual capture items.
 *
 * Port of CaptureCore's `MarkdownListParser` (Swift) — keep the two in sync. Recognises
 * bullet (`-`, `*`, `+`), numbered (`1.`, `2)`) and GitHub checkbox (`- [ ]`, `- [x]`) lists.
 * Indentation expresses nesting: each ancestor line's text becomes a "project" tag on its
 * descendants (projects = tags). Inline `#tags` are extracted and stripped from the title.
 * A ticked checkbox marks the item done. Pure + deterministic so it can be unit-tested.
 */

export interface ParsedCaptureItem {
  title: string;
  isDone: boolean;
  tags: string[];
}

interface ListLine {
  indent: number;
  title: string;
  isDone: boolean;
  hasCheckbox: boolean;
  inlineTags: string[];
  isList: boolean;
}

const MARKER = /^(\s*)(?:[-*+]|\d+[.)])\s+(.*)$/;
const CHECKBOX = /^\[([ xX])\]\s+(.*)$/;
// Unicode letters/numbers; `u` flag so \p{L}/\p{N} work.
const HASHTAG = /(?:^|\s)#([\p{L}\p{N}][\p{L}\p{N}_-]*)/gu;

function parseLine(raw: string): ListLine | null {
  const m = MARKER.exec(raw);
  if (!m) return null;
  const indentStr = m[1];
  let indent = 0;
  for (const ch of indentStr) indent += ch === '\t' ? 4 : 1;
  let content = m[2];

  let isDone = false;
  let hasCheckbox = false;
  const cb = CHECKBOX.exec(content);
  if (cb) {
    hasCheckbox = true;
    isDone = cb[1] === 'x' || cb[1] === 'X';
    content = cb[2];
  }

  const inlineTags = extractTags(content);
  const title = stripTags(content).trim();
  return { indent, title, isDone, hasCheckbox, inlineTags, isList: true };
}

function extractTags(s: string): string[] {
  const out: string[] = [];
  for (const m of s.matchAll(HASHTAG)) out.push(m[1]);
  return out;
}

function stripTags(s: string): string {
  return s.replace(HASHTAG, '').replace(/ {2}/g, ' ');
}

function dedupe(tags: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const t of tags) {
    const key = t.toLowerCase();
    if (t && !seen.has(key)) {
      seen.add(key);
      out.push(t);
    }
  }
  return out;
}

function depthForIndent(indent: number, stack: number[]): number {
  while (stack.length && indent < stack[stack.length - 1]) stack.pop();
  if (stack.length && indent === stack[stack.length - 1]) return stack.length - 1;
  stack.push(indent);
  return stack.length - 1;
}

/**
 * Returns one item per list line, or `null` if the text does not look like a list (in which
 * case the caller treats it as a single ordinary capture).
 */
export function parseMarkdownList(text: string): ParsedCaptureItem[] | null {
  const rawLines = text.split(/\r\n|\r|\n/);
  const parsed: { depth: number; line: ListLine }[] = [];
  let nonEmptyCount = 0;
  const indentStack: number[] = [];

  for (const raw of rawLines) {
    if (raw.trim() === '') continue;
    nonEmptyCount += 1;
    const line = parseLine(raw);
    if (!line) {
      parsed.push({ depth: -1, line: { indent: -1, title: '', isDone: false, hasCheckbox: false, inlineTags: [], isList: false } });
      continue;
    }
    const depth = depthForIndent(line.indent, indentStack);
    parsed.push({ depth, line });
  }

  const listLines = parsed.filter((p) => p.line.isList);
  const hasCheckbox = listLines.some((p) => p.line.hasCheckbox);
  if (listLines.length === 0) return null;
  if (listLines.length < 2 && !hasCheckbox) return null;
  if (listLines.length * 2 < nonEmptyCount) return null;

  const items: ParsedCaptureItem[] = [];
  const ancestors: { depth: number; title: string }[] = [];

  for (const entry of parsed) {
    if (!entry.line.isList) continue;
    while (ancestors.length && ancestors[ancestors.length - 1].depth >= entry.depth) {
      ancestors.pop();
    }
    const projectTags = ancestors.map((a) => a.title);
    const tags = dedupe([...projectTags, ...entry.line.inlineTags]);
    items.push({ title: entry.line.title, isDone: entry.line.isDone, tags });
    ancestors.push({ depth: entry.depth, title: entry.line.title });
  }

  return items;
}
