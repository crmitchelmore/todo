export type UserMemoryStatus = 'active' | 'disabled' | 'deleted';
export type UserMemorySource = 'manual' | 'correction' | 'inferred' | 'agent';

export interface UserMemoryInput {
  content: string;
  domain: string | null;
  source?: UserMemorySource;
  confidence?: number;
  tags: string[];
  status?: UserMemoryStatus;
  expires_at: string | null;
}

export function cleanUserMemoryInput(input: UserMemoryInput): Required<UserMemoryInput> | null {
  const content = input.content.trim().slice(0, 1000);
  if (!content) return null;
  const status = input.status === 'disabled' || input.status === 'deleted' ? input.status : 'active';
  return {
    content,
    domain: input.domain?.trim().slice(0, 80) || null,
    source: input.source ?? 'manual',
    confidence: Math.max(0, Math.min(1, input.confidence ?? 1)),
    tags: normalizeMemoryTags(input.tags).map((tag) => tag.slice(0, 80)),
    status,
    expires_at: input.expires_at,
  };
}

function normalizeMemoryTags(tags: unknown): string[] {
  if (!Array.isArray(tags)) return [];
  const seen = new Set<string>();
  const out: string[] = [];
  for (const tag of tags) {
    if (typeof tag !== 'string') continue;
    const trimmed = tag.trim();
    const key = trimmed.toLowerCase();
    if (trimmed && !seen.has(key)) {
      seen.add(key);
      out.push(trimmed);
    }
  }
  return out;
}

export function randomUserMemoryId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = Math.random() * 16 | 0;
    const v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}

export function parseMemoryExpiry(value: string): string | null {
  if (!value) return null;
  const date = new Date(`${value}T23:59:59.000Z`);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}
