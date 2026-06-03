import { db, ownerId } from '../powersync/db';

/** Fixed, pleasant chip palette. New tags get a stable colour derived from their name so
 *  they look consistent across clients (mirrors Swift `TagPalette`). */
export const TAG_COLORS = [
  '#E5484D', '#E54666', '#F76B15', '#FFB224', '#46A758', '#12A594',
  '#0091FF', '#3E63DD', '#8E4EC6', '#D6409F', '#9BA1A6', '#A18072'
];

export function colorForTag(name: string): string {
  const key = name.toLowerCase();
  // 64-bit FNV-1a (matches Swift), computed with BigInt to avoid precision loss.
  let hash = 1469598103934665603n;
  const prime = 1099511628211n;
  const mask = (1n << 64n) - 1n;
  for (let i = 0; i < key.length; i++) {
    hash = (hash ^ BigInt(key.charCodeAt(i) & 0xff)) & mask;
    hash = (hash * prime) & mask;
  }
  return TAG_COLORS[Number(hash % BigInt(TAG_COLORS.length))];
}

export function tagKey(name: string): string {
  return name.trim().toLowerCase();
}

/** Trim, drop empties, dedupe case-insensitively (keep first spelling). */
export function normalizeTags(tags: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const t of tags) {
    const trimmed = t.trim();
    const key = trimmed.toLowerCase();
    if (trimmed && !seen.has(key)) {
      seen.add(key);
      out.push(trimmed);
    }
  }
  return out;
}

export function encodeTags(tags: string[]): string | null {
  const cleaned = normalizeTags(tags);
  return cleaned.length ? JSON.stringify(cleaned) : null;
}

export function decodeTags(raw: string | null | undefined): string[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.filter((t) => typeof t === 'string') : [];
  } catch {
    return [];
  }
}

export interface TagMeta {
  id: string;
  name: string;
  color: string;
}

/** Create any tags that don't already exist (case-insensitive), auto-colouring new ones. */
export async function ensureTags(names: string[]): Promise<void> {
  for (const name of normalizeTags(names)) {
    const existing = await db.getOptional<{ id: string }>(
      `SELECT id FROM tags WHERE name = ? COLLATE NOCASE`,
      [name]
    );
    if (existing) continue;
    const now = new Date().toISOString();
    await db.execute(
      `INSERT INTO tags (id, owner_id, name, color, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [crypto.randomUUID(), ownerId(), name, colorForTag(name), now, now]
    );
  }
}

export async function createTag(name: string, color?: string): Promise<string | null> {
  const trimmed = name.trim();
  if (!trimmed) return null;
  const existing = await db.getOptional<{ id: string }>(
    `SELECT id FROM tags WHERE name = ? COLLATE NOCASE`,
    [trimmed]
  );
  if (existing) return existing.id;
  const id = crypto.randomUUID();
  const now = new Date().toISOString();
  await db.execute(
    `INSERT INTO tags (id, owner_id, name, color, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [id, ownerId(), trimmed, color ?? colorForTag(trimmed), now, now]
  );
  return id;
}

export async function recolorTag(id: string, color: string): Promise<void> {
  await db.execute(`UPDATE tags SET color = ?, updated_at = ? WHERE id = ?`, [
    color,
    new Date().toISOString(),
    id
  ]);
}

export async function renameTag(id: string, newName: string): Promise<void> {
  const trimmed = newName.trim();
  if (!trimmed) return;
  const now = new Date().toISOString();
  const row = await db.getOptional<{ name: string }>(`SELECT name FROM tags WHERE id = ?`, [id]);
  if (!row) return;
  if (tagKey(row.name) === tagKey(trimmed)) {
    // Pure case change: keep the row, fix spelling everywhere.
    await db.execute(`UPDATE tags SET name = ?, updated_at = ? WHERE id = ?`, [trimmed, now, id]);
    await rewriteTagOnTasks(row.name, trimmed);
    return;
  }
  const collision = await db.getOptional<{ id: string }>(
    `SELECT id FROM tags WHERE name = ? COLLATE NOCASE AND id <> ?`,
    [trimmed, id]
  );
  if (collision) {
    // Merge into the existing tag (the unique(owner, lower(name)) index forbids two rows).
    await rewriteTagOnTasks(row.name, trimmed);
    await db.execute(`DELETE FROM tags WHERE id = ?`, [id]);
  } else {
    await db.execute(`UPDATE tags SET name = ?, updated_at = ? WHERE id = ?`, [trimmed, now, id]);
    await rewriteTagOnTasks(row.name, trimmed);
  }
}

export async function deleteTag(id: string): Promise<void> {
  const row = await db.getOptional<{ name: string }>(`SELECT name FROM tags WHERE id = ?`, [id]);
  await db.execute(`DELETE FROM tags WHERE id = ?`, [id]);
  if (row) await rewriteTagOnTasks(row.name, null);
}

/** Rewrite a tag name on every task that references it. `to === null` removes it. */
async function rewriteTagOnTasks(oldName: string, to: string | null): Promise<void> {
  const key = tagKey(oldName);
  const rows = await db.getAll<{ id: string; tags: string | null }>(
    `SELECT id, tags FROM tasks WHERE tags LIKE ?`,
    [`%${oldName}%`]
  );
  const now = new Date().toISOString();
  for (const r of rows) {
    const current = decodeTags(r.tags);
    if (!current.some((t) => tagKey(t) === key)) continue;
    const updated = current.filter((t) => tagKey(t) !== key);
    if (to) updated.push(to);
    await db.execute(`UPDATE tasks SET tags = ?, updated_at = ? WHERE id = ?`, [
      encodeTags(updated),
      now,
      r.id
    ]);
  }
}
