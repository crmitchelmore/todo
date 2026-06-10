import { db, ownerId } from '../powersync/db';
import { encodeTags, normalizeTags } from './tags';

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

function clean(input: UserMemoryInput): Required<UserMemoryInput> | null {
  const content = input.content.trim().slice(0, 1000);
  if (!content) return null;
  const status = input.status === 'disabled' || input.status === 'deleted' ? input.status : 'active';
  return {
    content,
    domain: input.domain?.trim().slice(0, 80) || null,
    source: input.source ?? 'manual',
    confidence: Math.max(0, Math.min(1, input.confidence ?? 1)),
    tags: normalizeTags(input.tags).map((tag) => tag.slice(0, 80)),
    status,
    expires_at: input.expires_at,
  };
}

export async function createUserMemory(input: UserMemoryInput): Promise<string | null> {
  const cleaned = clean(input);
  if (!cleaned) return null;
  const id = randomId();
  const now = new Date().toISOString();
  await db.execute(
    `INSERT INTO user_memories
       (id, owner_id, content, domain, source, confidence, tags, status, expires_at, created_at, updated_at, deleted_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      id,
      ownerId(),
      cleaned.content,
      cleaned.domain,
      cleaned.source,
      cleaned.confidence,
      encodeTags(cleaned.tags),
      cleaned.status,
      cleaned.expires_at,
      now,
      now,
      cleaned.status === 'deleted' ? now : null,
    ]
  );
  return id;
}

function randomId(): string {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = Math.random() * 16 | 0;
    const v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}

export async function updateUserMemory(id: string, input: UserMemoryInput): Promise<void> {
  const cleaned = clean(input);
  if (!cleaned) return;
  const now = new Date().toISOString();
  await db.execute(
    `UPDATE user_memories
        SET content = ?, domain = ?, source = ?, confidence = ?, tags = ?, status = ?,
            expires_at = ?, updated_at = ?, deleted_at = ?
      WHERE id = ?`,
    [
      cleaned.content,
      cleaned.domain,
      cleaned.source,
      cleaned.confidence,
      encodeTags(cleaned.tags),
      cleaned.status,
      cleaned.expires_at,
      now,
      cleaned.status === 'deleted' ? now : null,
      id,
    ]
  );
}

export async function setUserMemoryStatus(id: string, status: UserMemoryStatus): Promise<void> {
  const now = new Date().toISOString();
  await db.execute(
    `UPDATE user_memories SET status = ?, updated_at = ?, deleted_at = ? WHERE id = ?`,
    [status, now, status === 'deleted' ? now : null, id]
  );
}
