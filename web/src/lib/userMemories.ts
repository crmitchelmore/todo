import { db, ownerId } from '../powersync/db';
import { encodeTags } from './tags';
import { cleanUserMemoryInput, randomUserMemoryId, type UserMemoryInput, type UserMemoryStatus } from './userMemoryModel';

export async function createUserMemory(input: UserMemoryInput): Promise<string | null> {
  const cleaned = cleanUserMemoryInput(input);
  if (!cleaned) return null;
  const id = randomUserMemoryId();
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

export async function updateUserMemory(id: string, input: UserMemoryInput): Promise<void> {
  const cleaned = cleanUserMemoryInput(input);
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
