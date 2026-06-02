import { db, OWNER_ID } from '../powersync/db';
import { suggest } from './suggest';

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
}

/** Promote a proposed item to a real (active) todo after the human confirms its structure. */
export async function confirm(id: string, fields: ConfirmFields): Promise<void> {
  const now = new Date().toISOString();
  await db.execute(
    `UPDATE tasks
       SET status = 'active',
           title = COALESCE(?, title),
           due_at = ?, category = ?, confirmed_at = ?, updated_at = ?
     WHERE id = ?`,
    [fields.title ?? null, fields.due_at ?? null, fields.category ?? null, now, now, id]
  );
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
