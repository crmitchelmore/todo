import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

export const URL_SUMMARY_SOURCE = 'url-summary';
export const URL_SUMMARY_DONE_SOURCE = 'url-summary';
export const URL_SUMMARY_FAILED_SOURCE = 'url-summary-failed';

const DEFAULT_TIMEOUT_MS = 12_000;
const MAX_SOURCE_CHARS = 18_000;

export interface UrlSummaryEnv {
  readonly OPENAI_API_KEY?: string;
  readonly OPENAI_BASE_URL?: string;
  readonly ENRICH_LLM_MODEL?: string;
  readonly HANDOFF_LLM_MODEL?: string;
  readonly URL_SUMMARY_LLM_MODEL?: string;
  readonly URL_SUMMARY_DEFUDDLE_COMMAND?: string;
  readonly URL_SUMMARY_DISABLE_DEFUDDLE?: string;
  readonly OBSIDIAN_CLI_ENABLED?: string;
  readonly OBSIDIAN_CLI_COMMAND?: string;
  readonly OBSIDIAN_VAULT?: string;
  readonly OBSIDIAN_SUMMARY_FOLDER?: string;
}

export type FetchLike = (input: string | URL, init?: RequestInit) => Promise<Response>;
export type RunCommand = (
  command: string,
  args: readonly string[],
  options: { timeoutMs: number }
) => Promise<{ stdout: string; stderr: string }>;

export interface UrlSummaryDocument {
  readonly url: string;
  readonly title: string;
  readonly overview: string;
  readonly paragraphs: readonly string[];
  readonly markdown: string;
  readonly obsidianPath: string | null;
  readonly model: string;
  readonly extractedChars: number;
}

interface SummaryPayload {
  title: string;
  overview: string;
  paragraphs: readonly string[];
}

export function urlOnlyCapture(raw: string): string | null {
  const trimmed = raw.trim();
  if (!trimmed || /\s/.test(trimmed)) return null;
  try {
    const url = new URL(trimmed);
    return url.protocol === 'http:' || url.protocol === 'https:' ? url.toString() : null;
  } catch {
    return null;
  }
}

export async function generateUrlSummaryDocument(
  url: string,
  options: {
    env?: UrlSummaryEnv;
    fetchImpl?: FetchLike;
    runCommand?: RunCommand;
    now?: Date;
  } = {}
): Promise<UrlSummaryDocument> {
  const env = options.env ?? process.env;
  const canonicalUrl = urlOnlyCapture(url);
  if (!canonicalUrl) throw new Error('URL summary requires a bare http(s) URL');

  const source = await extractReadableMarkdown(canonicalUrl, {
    env,
    fetchImpl: options.fetchImpl,
    runCommand: options.runCommand,
  });
  const { payload, model } = await summariseWithLLM(canonicalUrl, source, {
    env,
    fetchImpl: options.fetchImpl,
    now: options.now,
  });
  const markdown = renderObsidianMarkdown(canonicalUrl, payload, options.now ?? new Date());
  const obsidianPath = await writeToObsidian(markdown, payload.title, {
    env,
    runCommand: options.runCommand,
    now: options.now,
  });
  return {
    url: canonicalUrl,
    title: payload.title,
    overview: payload.overview,
    paragraphs: payload.paragraphs,
    markdown,
    obsidianPath,
    model,
    extractedChars: source.length,
  };
}

async function extractReadableMarkdown(
  url: string,
  options: {
    env: UrlSummaryEnv;
    fetchImpl?: FetchLike;
    runCommand?: RunCommand;
  }
): Promise<string> {
  const defuddle = options.env.URL_SUMMARY_DISABLE_DEFUDDLE === '1'
    ? null
    : options.env.URL_SUMMARY_DEFUDDLE_COMMAND?.trim() || 'defuddle';
  if (defuddle) {
    try {
      const result = await runCommand(options.runCommand)(defuddle, ['parse', url, '--md'], { timeoutMs: DEFAULT_TIMEOUT_MS });
      const markdown = result.stdout.trim();
      if (markdown.length > 200) return markdown.slice(0, MAX_SOURCE_CHARS);
    } catch {
      // Fall through to bounded fetch extraction; the failure is not user-actionable by itself.
    }
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);
  try {
    const response = await (options.fetchImpl ?? fetch)(url, {
      headers: { Accept: 'text/markdown, text/html;q=0.9, text/plain;q=0.8, */*;q=0.1' },
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`fetch failed: HTTP ${response.status}`);
    const text = await response.text();
    const contentType = response.headers.get('content-type') ?? '';
    const readable = contentType.includes('html') ? htmlToReadableText(text) : text;
    const cleaned = readable.replace(/\n{3,}/g, '\n\n').trim();
    if (cleaned.length < 120) throw new Error('extracted page content was too short to summarise');
    return cleaned.slice(0, MAX_SOURCE_CHARS);
  } finally {
    clearTimeout(timeout);
  }
}

async function summariseWithLLM(
  url: string,
  sourceMarkdown: string,
  options: {
    env: UrlSummaryEnv;
    fetchImpl?: FetchLike;
    now?: Date;
  }
): Promise<{ payload: SummaryPayload; model: string }> {
  const apiKey = options.env.OPENAI_API_KEY?.trim();
  if (!apiKey) throw new Error('URL summary LLM is not configured: OPENAI_API_KEY is missing');

  const model = options.env.URL_SUMMARY_LLM_MODEL?.trim()
    || options.env.HANDOFF_LLM_MODEL?.trim()
    || options.env.ENRICH_LLM_MODEL?.trim()
    || 'gpt-4o-mini';
  const baseUrl = (options.env.OPENAI_BASE_URL?.trim() || 'https://api.openai.com/v1').replace(/\/$/, '');
  const response = await (options.fetchImpl ?? fetch)(`${baseUrl}/chat/completions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({
      model,
      temperature: 0.2,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: urlSummarySystemPrompt(options.now ?? new Date()) },
        { role: 'user', content: JSON.stringify({ url, content_markdown: sourceMarkdown.slice(0, MAX_SOURCE_CHARS) }) },
      ],
    }),
  });
  if (!response.ok) throw new Error(`URL summary LLM failed: HTTP ${response.status}`);
  const json = await response.json() as any;
  const content = json.choices?.[0]?.message?.content;
  if (typeof content !== 'string' || !content.trim()) throw new Error('URL summary LLM failed: empty response');
  return { payload: parseSummaryPayload(content, url), model };
}

function urlSummarySystemPrompt(now: Date): string {
  return [
    'You summarise a single web page for Capture.',
    'Return strict JSON with keys: title, overview, summary_paragraphs.',
    'title: the page title or a concise descriptive title, max 90 characters.',
    'overview: 1-2 sentences that state the core point and why it matters.',
    'summary_paragraphs: array of 3-5 paragraphs, each 2-5 sentences, preserving the page meaning without inventing facts.',
    'Do not include markdown in the JSON fields.',
    `Current time: ${now.toISOString()}.`,
  ].join(' ');
}

export function parseSummaryPayload(content: string, url: string): SummaryPayload {
  let parsed: unknown;
  try {
    parsed = JSON.parse(content);
  } catch {
    throw new Error('URL summary LLM failed: invalid JSON response');
  }
  if (!isRecord(parsed)) throw new Error('URL summary LLM failed: response is not an object');

  const title = boundedString(parsed.title, 90) ?? new URL(url).hostname;
  const overview = overviewSentences(boundedString(parsed.overview, 900));
  const paragraphs = paragraphArray(parsed.summary_paragraphs ?? parsed.summary)
    .map((paragraph) => paragraph.slice(0, 1200))
    .slice(0, 5);
  if (!overview) throw new Error('URL summary LLM failed: response missing overview');
  if (paragraphs.length < 3) throw new Error('URL summary LLM failed: response needs 3-5 summary paragraphs');
  return { title, overview, paragraphs };
}

export function renderObsidianMarkdown(url: string, payload: SummaryPayload, now: Date): string {
  return [
    '---',
    `title: ${yamlString(payload.title)}`,
    `source: ${yamlString(url)}`,
    `created: ${yamlString(now.toISOString())}`,
    'tags:',
    '  - capture/url-summary',
    '---',
    '',
    `# ${payload.title}`,
    '',
    `Source: [${new URL(url).hostname}](${url})`,
    '',
    '> [!summary] Overview',
    `> ${payload.overview.replace(/\n+/g, ' ')}`,
    '',
    '## Summary',
    '',
    ...payload.paragraphs.flatMap((paragraph) => [paragraph, '']),
  ].join('\n').trimEnd() + '\n';
}

async function writeToObsidian(
  markdown: string,
  title: string,
  options: {
    env: UrlSummaryEnv;
    runCommand?: RunCommand;
    now?: Date;
  }
): Promise<string | null> {
  const command = options.env.OBSIDIAN_CLI_COMMAND?.trim()
    || (options.env.OBSIDIAN_CLI_ENABLED === '1' || options.env.OBSIDIAN_VAULT?.trim() ? 'obsidian' : '');
  if (!command) return null;

  const folder = cleanFolder(options.env.OBSIDIAN_SUMMARY_FOLDER) ?? 'Capture/Summaries';
  const path = `${folder}/${dateStamp(options.now ?? new Date())}-${slugify(title)}.md`;
  const args = [
    'create',
    ...(options.env.OBSIDIAN_VAULT?.trim() ? [`vault=${options.env.OBSIDIAN_VAULT.trim()}`] : []),
    `path=${path}`,
    `content=${markdown}`,
    'silent',
    'overwrite',
  ];
  await runCommand(options.runCommand)(command, args, { timeoutMs: DEFAULT_TIMEOUT_MS });
  return path;
}

function runCommand(command?: RunCommand): RunCommand {
  if (command) return command;
  return async (cmd, args, options) => {
    const result = await execFileAsync(cmd, [...args], {
      timeout: options.timeoutMs,
      maxBuffer: 1024 * 1024,
    });
    return { stdout: result.stdout, stderr: result.stderr };
  };
}

function htmlToReadableText(html: string): string {
  return decodeEntities(
    html
      .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ')
      .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
      .replace(/<nav\b[^>]*>[\s\S]*?<\/nav>/gi, ' ')
      .replace(/<header\b[^>]*>[\s\S]*?<\/header>/gi, ' ')
      .replace(/<footer\b[^>]*>[\s\S]*?<\/footer>/gi, ' ')
      .replace(/<\/(h[1-6]|p|li|blockquote|article|section|div)>/gi, '\n\n')
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<[^>]+>/g, ' ')
      .replace(/[ \t]{2,}/g, ' ')
      .replace(/\n[ \t]+/g, '\n')
  );
}

function decodeEntities(value: string): string {
  return value
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

function paragraphArray(value: unknown): string[] {
  if (Array.isArray(value)) return value.map((item) => boundedString(item, 1400)).filter((item): item is string => Boolean(item));
  if (typeof value === 'string') {
    return value
      .split(/\n{2,}/)
      .map((paragraph) => paragraph.replace(/\s+/g, ' ').trim())
      .filter(Boolean);
  }
  return [];
}

function overviewSentences(value: string | null): string | null {
  if (!value) return null;
  const sentences = value.match(/[^.!?]+[.!?]+(?:\s|$)|[^.!?]+$/g)
    ?.map((sentence) => sentence.trim())
    .filter(Boolean) ?? [value];
  return sentences.slice(0, 2).join(' ').trim() || null;
}

function boundedString(value: unknown, max: number): string | null {
  return typeof value === 'string' && value.trim() ? value.trim().replace(/\s+/g, ' ').slice(0, max) : null;
}

function yamlString(value: string): string {
  return JSON.stringify(value);
}

function dateStamp(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function slugify(value: string): string {
  const slug = value
    .toLowerCase()
    .replace(/['"]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 72);
  return slug || 'url-summary';
}

function cleanFolder(value: string | undefined): string | null {
  const trimmed = value?.trim().replace(/^\/+|\/+$/g, '');
  return trimmed && trimmed.length > 0 ? trimmed : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
