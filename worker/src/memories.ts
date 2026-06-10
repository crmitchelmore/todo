import type pg from 'pg';
import type { MemoryContext } from './discovery.js';

export const ACTIVE_MEMORIES_SQL = `
  SELECT content, domain, source, confidence, tags, expires_at
  FROM public.user_memories
  WHERE owner_id = $1
    AND status = 'active'
    AND (expires_at IS NULL OR expires_at > now())
  ORDER BY confidence DESC, updated_at DESC
  LIMIT 24
`;

export interface MemoryRow {
  content: string;
  domain: string | null;
  source: string;
  confidence: number;
  tags: string | null;
  expires_at: string | Date | null;
}

export function decodeMemoryTags(raw: string | null): string[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw) as unknown;
    return Array.isArray(parsed) ? parsed.filter((tag): tag is string => typeof tag === 'string') : [];
  } catch {
    return [];
  }
}

export function mapMemoryRow(row: MemoryRow): MemoryContext {
  return {
    content: row.content,
    domain: row.domain,
    source: row.source,
    confidence: Number(row.confidence),
    tags: decodeMemoryTags(row.tags),
    expiresAt: row.expires_at instanceof Date ? row.expires_at.toISOString() : row.expires_at,
  };
}

export async function loadActiveMemories(
  pool: Pick<pg.Pool, 'query'>,
  ownerId: string
): Promise<MemoryContext[]> {
  const { rows } = await pool.query<MemoryRow>(ACTIVE_MEMORIES_SQL, [ownerId]);
  return rows.map(mapMemoryRow);
}

export function compactMemories(memories: readonly MemoryContext[]): Array<Record<string, unknown>> {
  return memories.slice(0, 5).map((memory) => ({
    content: memory.content.slice(0, 220),
    domain: memory.domain,
    source: memory.source,
    confidence: memory.confidence,
    tags: memory.tags.slice(0, 6),
    expires_at: memory.expiresAt,
  }));
}
