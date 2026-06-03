import { db, OWNER_ID } from '../powersync/db';
import { suggest } from './suggest';
import { parseMarkdownList, type ParsedCaptureItem } from './markdownList';
import { encodeTags, ensureTags, normalizeTags } from './tags';

/**
 * Capture is the hot path: ONE instant local INSERT, nothing awaited on the network or an LLM.
 * Enrichment is fired off in the background and patches the row when ready.
 */
export async function capture(raw: string): Promise<string> {
  const title = raw.trim();
  if (!title) return '';
  const id = crypto.randomUUID();
  const now = new Date().toISOString();
  await db.execute(
    `INSERT INTO tasks (id, owner_id, title, status, source, created_at, updated_at)
     VALUES (?, ?, ?, 'proposed', 'capture', ?, ?)`,
    [id, OWNER_ID, title, now, now]
  );
  void enrich(id, title);
  return id;
}

async function enrich(id: string, title: string): Promise<void> {
  const s = suggest(title);
  const now = new Date().toISOString();
  await db.execute(
    `UPDATE tasks
       SET suggested_due_at = ?, suggested_category = ?, suggestion_confidence = ?,
           suggestion_source = 'on-device', updated_at = ?
     WHERE id = ?`,
    [s.dueAt, s.category, s.confidence, now, id]
  );
}

export interface ConfirmFields {
  title?: string;
  due_at?: string | null;
  category?: string | null;
  tags?: string[];
}

/**
 * If `raw` is a markdown / checkbox list, capture each line as its own item (active items land
 * in the proposed inbox; `[x]` items import directly as done). Otherwise returns null and the
 * caller should fall back to single `capture`.
 */
export async function captureList(raw: string): Promise<string[] | null> {
  const items = parseMarkdownList(raw);
  if (!items) return null;
  return captureBatch(items);
}

export async function captureBatch(items: ParsedCaptureItem[]): Promise<string[]> {
  const prepared = items
    .filter((i) => i.title.trim().length > 0)
    .map((item) => ({ id: crypto.randomUUID(), item }));
  if (prepared.length === 0) return [];
  await ensureTags(prepared.flatMap((p) => p.item.tags));
  for (const { id, item } of prepared) {
    const now = new Date().toISOString();
    const tagsJSON = encodeTags(item.tags);
    if (item.isDone) {
      await db.execute(
        `INSERT INTO tasks
           (id, owner_id, title, status, category, tags, source, created_at, updated_at, confirmed_at, completed_at)
         VALUES (?, ?, ?, 'done', NULL, ?, 'paste', ?, ?, ?, ?)`,
        [id, OWNER_ID, item.title, tagsJSON, now, now, now, now]
      );
    } else {
      await db.execute(
        `INSERT INTO tasks (id, owner_id, title, status, tags, source, created_at, updated_at)
         VALUES (?, ?, ?, 'proposed', ?, 'paste', ?, ?)`,
        [id, OWNER_ID, item.title, tagsJSON, now, now]
      );
      void enrich(id, item.title);
    }
  }
  return prepared.map((p) => p.id);
}

/** Promote a proposed item to a real (active) todo after the human confirms its structure. */
export async function confirm(id: string, fields: ConfirmFields): Promise<void> {
  const now = new Date().toISOString();
  if (fields.tags) await ensureTags(normalizeTags(fields.tags));
  const tagsJSON = fields.tags ? encodeTags(fields.tags) ?? '[]' : null;
  await db.execute(
    `UPDATE tasks
       SET status = 'active',
           title = COALESCE(?, title),
           due_at = ?, category = ?, tags = COALESCE(?, tags),
           confirmed_at = ?, updated_at = ?
     WHERE id = ?`,
    [fields.title ?? null, fields.due_at ?? null, fields.category ?? null, tagsJSON, now, now, id]
  );
}

/** Replace the tag set on an existing task (inline editing on a row). */
export async function setTags(id: string, tags: string[]): Promise<void> {
  const normalized = normalizeTags(tags);
  await ensureTags(normalized);
  await db.execute(`UPDATE tasks SET tags = ?, updated_at = ? WHERE id = ?`, [
    encodeTags(normalized) ?? '[]',
    new Date().toISOString(),
    id
  ]);
}

/** Set or clear the due date on any task (used by inline date editing on a row). */
export async function setDue(id: string, dueIso: string | null): Promise<void> {
  await db.execute(`UPDATE tasks SET due_at = ?, updated_at = ? WHERE id = ?`, [
    dueIso,
    new Date().toISOString(),
    id
  ]);
}

export async function reject(id: string): Promise<void> {
  await db.execute(`DELETE FROM tasks WHERE id = ?`, [id]);
}

export async function setDone(id: string, done: boolean): Promise<void> {
  const now = new Date().toISOString();
  await db.execute(
    `UPDATE tasks SET status = ?, completed_at = ?, updated_at = ? WHERE id = ?`,
    [done ? 'done' : 'active', done ? now : null, now, id]
  );
}
