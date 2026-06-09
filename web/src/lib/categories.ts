import { db, ownerId } from '../powersync/db';
import { colorForTag, tagKey } from './tags';

export const DEFAULT_CATEGORIES = ['engineering', 'leadership', 'home', 'errands', 'health', 'finance', 'personal', 'inbox'];

export function colorForCategory(name: string): string {
  return colorForTag(name);
}

export async function createCategory(name: string, color?: string): Promise<string | null> {
  const trimmed = name.trim();
  if (!trimmed) return null;
  const existing = await db.getOptional<{ id: string }>(
    `SELECT id FROM categories WHERE name = ? COLLATE NOCASE`,
    [trimmed]
  );
  if (existing) return existing.id;
  const id = crypto.randomUUID();
  const now = new Date().toISOString();
  await db.execute(
    `INSERT INTO categories (id, owner_id, name, color, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [id, ownerId(), trimmed, color ?? colorForCategory(trimmed), now, now]
  );
  return id;
}

export async function recolorCategory(id: string, color: string): Promise<void> {
  await db.execute(`UPDATE categories SET color = ?, updated_at = ? WHERE id = ?`, [
    color,
    new Date().toISOString(),
    id
  ]);
}

export async function renameCategory(id: string, newName: string): Promise<void> {
  const trimmed = newName.trim();
  if (!trimmed) return;
  const now = new Date().toISOString();
  const row = await db.getOptional<{ name: string }>(`SELECT name FROM categories WHERE id = ?`, [id]);
  if (!row) return;
  if (tagKey(row.name) === tagKey(trimmed)) {
    await db.execute(`UPDATE categories SET name = ?, updated_at = ? WHERE id = ?`, [trimmed, now, id]);
    await rewriteCategoryOnTasks(row.name, trimmed);
    return;
  }
  const collision = await db.getOptional<{ id: string }>(
    `SELECT id FROM categories WHERE name = ? COLLATE NOCASE AND id <> ?`,
    [trimmed, id]
  );
  if (collision) {
    await rewriteCategoryOnTasks(row.name, trimmed);
    await db.execute(`DELETE FROM categories WHERE id = ?`, [id]);
  } else {
    await db.execute(`UPDATE categories SET name = ?, updated_at = ? WHERE id = ?`, [trimmed, now, id]);
    await rewriteCategoryOnTasks(row.name, trimmed);
  }
}

export async function deleteCategory(id: string): Promise<void> {
  const row = await db.getOptional<{ name: string }>(`SELECT name FROM categories WHERE id = ?`, [id]);
  await db.execute(`DELETE FROM categories WHERE id = ?`, [id]);
  if (row) await rewriteCategoryOnTasks(row.name, null);
}

async function rewriteCategoryOnTasks(oldName: string, to: string | null): Promise<void> {
  await db.execute(
    `UPDATE tasks SET category = ?, updated_at = ? WHERE category = ? COLLATE NOCASE`,
    [to, new Date().toISOString(), oldName]
  );
}
