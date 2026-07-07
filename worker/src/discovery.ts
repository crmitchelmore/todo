import { urlOnlyCapture } from './urlSummary.js';

export interface DiscoveryTask {
  id: string;
  ownerId: string;
  title: string;
}

export interface LocationContext {
  source: 'env' | 'unavailable';
  label: string | null;
  latitude: number | null;
  longitude: number | null;
  timeZone: string | null;
}

export interface WebSearchResult {
  title: string;
  url: string | null;
  snippet: string | null;
}

export interface WebContext {
  source: 'configured_endpoint' | 'direct_url' | 'not_configured' | 'error';
  query: string;
  results: WebSearchResult[];
  error?: string;
}

export interface MemoryContext {
  content: string;
  domain: string | null;
  source: string;
  confidence: number;
  tags: string[];
  expiresAt: string | null;
}

export interface TaskDiscovery {
  taskId: string;
  title: string;
  query: string;
  location: LocationContext;
  web: WebContext;
  memories: MemoryContext[];
  nextActions: string[];
  confidence: number;
}

export type FetchLike = (input: string | URL, init?: RequestInit) => Promise<Response>;

export interface DiscoveryEnv {
  readonly CAPTURE_LOCATION_LABEL?: string;
  readonly CAPTURE_LOCATION_LATITUDE?: string;
  readonly CAPTURE_LOCATION_LONGITUDE?: string;
  readonly CAPTURE_TIME_ZONE?: string;
  readonly CAPTURE_WEB_SEARCH_ENDPOINT?: string;
  readonly CAPTURE_WEB_SEARCH_API_KEY?: string;
  readonly CAPTURE_WEB_SEARCH_TIMEOUT_MS?: string;
}

const WEB_DISCOVERY_HINTS = [
  'research',
  'find',
  'look up',
  'compare',
  'best',
  'price',
  'review',
  'reviews',
  'where to',
  'opening hours',
  'book',
  'reserve',
];

const LOCATION_HINTS = [
  'near me',
  'nearby',
  'local',
  'closest',
  'around here',
  'directions',
  'commute',
  'restaurant',
  'cafe',
  'shop',
  'pharmacy',
  'dentist',
  'doctor',
  'gym',
];

export function shouldDiscoverTask(title: string): boolean {
  const normalized = title.toLowerCase();
  return WEB_DISCOVERY_HINTS.some((hint) => normalized.includes(hint)) ||
    LOCATION_HINTS.some((hint) => normalized.includes(hint));
}

export function locationContextFromEnv(env: DiscoveryEnv = process.env): LocationContext {
  const label = nonEmpty(env.CAPTURE_LOCATION_LABEL);
  const latitude = toCoordinate(env.CAPTURE_LOCATION_LATITUDE, -90, 90);
  const longitude = toCoordinate(env.CAPTURE_LOCATION_LONGITUDE, -180, 180);
  const timeZone = nonEmpty(env.CAPTURE_TIME_ZONE) ?? Intl.DateTimeFormat().resolvedOptions().timeZone ?? null;
  if (!label && latitude === null && longitude === null) {
    return { source: 'unavailable', label: null, latitude: null, longitude: null, timeZone };
  }
  return { source: 'env', label: label ?? null, latitude, longitude, timeZone };
}

export function discoveryQueryFor(title: string, location: LocationContext): string {
  const normalized = title.replace(/\s+/g, ' ').trim();
  if (!needsLocation(title)) return normalized;
  if (location.label) return `${normalized} ${location.label}`;
  if (location.latitude !== null && location.longitude !== null) {
    return `${normalized} near ${location.latitude.toFixed(4)},${location.longitude.toFixed(4)}`;
  }
  return normalized;
}

export async function discoverTaskContext(
  task: DiscoveryTask,
  options: {
    env?: DiscoveryEnv;
    fetchImpl?: FetchLike;
    now?: Date;
    force?: boolean;
    instructions?: string | null;
    memories?: readonly MemoryContext[];
  } = {}
): Promise<TaskDiscovery | null> {
  if (!options.force && !shouldDiscoverTask(task.title)) return null;
  const env = options.env ?? process.env;
  const location = locationContextFromEnv(env);
  const memories = options.memories?.slice(0, 12) ?? [];
  const memoryQuery = memories.map((memory) => memory.content).join(' ');
  const querySeed = [task.title, options.instructions ?? '', memoryQuery].join(' ').replace(/\s+/g, ' ').trim();
  const query = discoveryQueryFor(querySeed || task.title, location).slice(0, 500);
  const directUrl = urlOnlyCapture(task.title);
  const web = directUrl
    ? await fetchUrlContext(directUrl, env, options.fetchImpl ?? fetch)
    : await fetchWebContext(query, env, options.fetchImpl ?? fetch);
  const nextActions = nextActionsFor(querySeed || task.title, location, web, memories);
  const confidence = discoveryConfidence(location, web);

  return {
    taskId: task.id,
    title: task.title,
    query,
    location,
    web,
    memories,
    nextActions,
    confidence,
  };
}

async function fetchWebContext(query: string, env: DiscoveryEnv, fetchImpl: FetchLike): Promise<WebContext> {
  const endpoint = nonEmpty(env.CAPTURE_WEB_SEARCH_ENDPOINT);
  if (!endpoint) {
    return { source: 'not_configured', query, results: [] };
  }

  const url = new URL(endpoint);
  url.searchParams.set('q', query);
  const timeoutMs = toPositiveInt(env.CAPTURE_WEB_SEARCH_TIMEOUT_MS) ?? 2500;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const headers: Record<string, string> = { Accept: 'application/json' };
    const apiKey = nonEmpty(env.CAPTURE_WEB_SEARCH_API_KEY);
    if (apiKey) headers.Authorization = `Bearer ${apiKey}`;
    const response = await fetchImpl(url, { headers, signal: controller.signal });
    if (!response.ok) {
      return { source: 'error', query, results: [], error: `HTTP ${response.status}` };
    }
    const json = await response.json() as unknown;
    return { source: 'configured_endpoint', query, results: parseWebResults(json).slice(0, 5) };
  } catch (err) {
    return { source: 'error', query, results: [], error: err instanceof Error ? err.message : String(err) };
  } finally {
    clearTimeout(timeout);
  }
}

function parseWebResults(json: unknown): WebSearchResult[] {
  const rawResults = Array.isArray(json)
    ? json
    : isRecord(json) && Array.isArray(json.results)
      ? json.results
      : [];
  const out: WebSearchResult[] = [];
  for (const raw of rawResults) {
    if (!isRecord(raw)) continue;
    const title = valueAsString(raw.title ?? raw.name);
    if (!title) continue;
    out.push({
      title,
      url: valueAsString(raw.url ?? raw.link) ?? null,
      snippet: valueAsString(raw.snippet ?? raw.description ?? raw.content) ?? null,
    });
  }
  return out;
}

const HTML_MAX_PARSE_BYTES = 200_000;

async function fetchUrlContext(target: string, env: DiscoveryEnv, fetchImpl: FetchLike): Promise<WebContext> {
  const timeoutMs = toPositiveInt(env.CAPTURE_WEB_SEARCH_TIMEOUT_MS) ?? 4000;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchImpl(target, {
      headers: {
        Accept: 'text/html,application/xhtml+xml',
        'User-Agent': 'CaptureWorker/1.0 (+discovery)',
      },
      signal: controller.signal,
    });
    if (!response.ok) {
      return { source: 'error', query: target, results: [], error: `HTTP ${response.status}` };
    }
    const html = (await response.text()).slice(0, HTML_MAX_PARSE_BYTES);
    return { source: 'direct_url', query: target, results: [pageResultFromHtml(target, html)] };
  } catch (err) {
    return { source: 'error', query: target, results: [], error: err instanceof Error ? err.message : String(err) };
  } finally {
    clearTimeout(timeout);
  }
}

function pageResultFromHtml(url: string, html: string): WebSearchResult {
  return {
    title: extractHtmlTitle(html) ?? url,
    url,
    snippet: extractMetaDescription(html),
  };
}

function extractHtmlTitle(html: string): string | null {
  const og = html.match(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']/i);
  if (og) return normalizeHtmlText(og[1]);
  const title = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  if (title) return normalizeHtmlText(title[1]);
  return null;
}

function extractMetaDescription(html: string): string | null {
  const patterns = [
    /<meta[^>]+name=["']description["'][^>]+content=["']([^"']*)["']/i,
    /<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']*)["']/i,
    /<meta[^>]+content=["']([^"']*)["'][^>]+name=["']description["']/i,
  ];
  for (const pattern of patterns) {
    const match = html.match(pattern);
    const text = match ? normalizeHtmlText(match[1]) : null;
    if (text) return text.slice(0, 400);
  }
  return null;
}

function normalizeHtmlText(text: string): string | null {
  const decoded = text
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#0*39;|&#x0*27;|&apos;/gi, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return decoded.length > 0 ? decoded : null;
}

function nextActionsFor(title: string, location: LocationContext, web: WebContext, memories: readonly MemoryContext[] = []): string[] {
  const actions: string[] = [];
  for (const memory of memories.slice(0, 3)) {
    actions.push(`Apply user context: ${memory.content}`);
  }
  if (web.results.length > 0) {
    const top = web.results[0];
    actions.push(`Review top result: ${top.title}${top.url ? ` (${top.url})` : ''}`);
  } else if (urlOnlyCapture(web.query)) {
    actions.push(`Open the linked page directly: ${web.query}`);
  } else {
    actions.push(`Run web search for "${web.query}"`);
  }
  if (needsLocation(title)) {
    if (location.source === 'env') {
      actions.push(`Use current location context: ${location.label ?? `${location.latitude},${location.longitude}`}`);
    } else {
      actions.push('Add current location before choosing a nearby option');
    }
  }
  actions.push('Summarise findings into a confirmed next action before mutating external systems');
  return actions;
}

function discoveryConfidence(location: LocationContext, web: WebContext): number {
  const webScore = web.results.length > 0 ? 0.35 : web.source === 'error' ? 0.05 : 0.15;
  const locationScore = location.source === 'env' ? 0.15 : 0;
  return Math.min(0.85, Number((0.35 + webScore + locationScore).toFixed(2)));
}

function needsLocation(title: string): boolean {
  const normalized = title.toLowerCase();
  return LOCATION_HINTS.some((hint) => normalized.includes(hint));
}

function nonEmpty(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed && trimmed.length > 0 ? trimmed : undefined;
}

function toCoordinate(value: string | undefined, min: number, max: number): number | null {
  const trimmed = nonEmpty(value);
  if (!trimmed) return null;
  const n = Number(trimmed);
  return Number.isFinite(n) && n >= min && n <= max ? n : null;
}

function toPositiveInt(value: string | undefined): number | null {
  const trimmed = nonEmpty(value);
  if (!trimmed) return null;
  const n = Number(trimmed);
  return Number.isInteger(n) && n > 0 ? n : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function valueAsString(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : undefined;
}
