import { db, ownerId } from '../powersync/db';
import { config } from '../config';
import { getToken } from './auth';
import { suggest } from './suggest';
import { parseMarkdownList, type ParsedCaptureItem } from './markdownList';
import { encodeTags, ensureTags, normalizeTags } from './tags';
import type { AttachmentDraft } from './attachments';
import { URL_SUMMARY_SOURCE, urlOnlyCapture } from './urlSummary';

/**
 * Capture is the hot path: ONE instant local INSERT, nothing awaited on the network or an LLM.
 * Enrichment is fired off in the background and patches the row when ready.
 */
export async function capture(raw: string, attachments: AttachmentDraft[] = []): Promise<string> {
  const title = raw.trim();
  if (!title && attachments.length === 0) return '';
  const id = crypto.randomUUID();
  const now = new Date().toISOString();
  const summaryUrl = attachments.length === 0 ? urlOnlyCapture(title) : null;
  const effectiveTitle = summaryUrl ?? (title || attachments[0]?.filename || 'Image attachment');
  const source = summaryUrl ? URL_SUMMARY_SOURCE : 'capture';
  await db.execute(
    `INSERT INTO tasks (id, owner_id, title, status, source, created_at, updated_at)
     VALUES (?, ?, ?, 'proposed', ?, ?, ?)`,
    [id, ownerId(), effectiveTitle, source, now, now]
  );
  for (const attachment of attachments) {
    await addAttachment(id, attachment, now);
  }
  void enrich(id, effectiveTitle);
  return id;
}

export async function addAttachment(taskId: string, attachment: AttachmentDraft, createdAt = new Date().toISOString()): Promise<string> {
  const id = crypto.randomUUID();
  await db.execute(
    `INSERT INTO task_attachments
       (id, owner_id, task_id, filename, mime_type, byte_size, preview_data_url, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      id,
      ownerId(),
      taskId,
      attachment.filename,
      attachment.mime_type,
      attachment.byte_size,
      attachment.preview_data_url,
      createdAt,
    ]
  );
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
  notes?: string | null;
  due_at?: string | null;
  category?: string | null;
  tags?: string[];
  priority?: number | null;
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
    .map((item, itemIndex) => ({ id: crypto.randomUUID(), item, itemIndex }))
    .filter((p) => p.item.title.trim().length > 0);
  const idByItemIndex = new Map(prepared.map((p) => [p.itemIndex, p.id]));
  if (prepared.length === 0) return [];
  await ensureTags(prepared.flatMap((p) => p.item.tags));
  for (const { id, item } of prepared) {
    const now = new Date().toISOString();
    const tagsJSON = encodeTags(item.tags);
    const parentId =
      typeof item.parentIndex === 'number'
        ? idByItemIndex.get(item.parentIndex) ?? null
        : null;
    if (item.isDone) {
      await db.execute(
        `INSERT INTO tasks
           (id, owner_id, parent_task_id, title, status, category, tags, source, created_at, updated_at, confirmed_at, completed_at)
         VALUES (?, ?, ?, ?, 'done', NULL, ?, 'paste', ?, ?, ?, ?)`,
        [id, ownerId(), parentId, item.title, tagsJSON, now, now, now, now]
      );
    } else {
      await db.execute(
        `INSERT INTO tasks (id, owner_id, parent_task_id, title, status, tags, source, created_at, updated_at)
         VALUES (?, ?, ?, ?, 'proposed', ?, 'paste', ?, ?)`,
        [id, ownerId(), parentId, item.title, tagsJSON, now, now]
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
           notes = COALESCE(?, notes),
           due_at = ?, category = ?, tags = COALESCE(?, tags), priority = ?,
           confirmed_at = ?, updated_at = ?
     WHERE id = ?`,
    [
     fields.title ?? null,
     fields.notes ?? null,
     fields.due_at ?? null,
     fields.category ?? null,
     tagsJSON,
     fields.priority ?? null,
     now,
     now,
     id
    ]
  );
}

export interface TaskUpdateFields {
  title?: string;
  notes?: string | null;
  due_at?: string | null;
  category?: string | null;
  tags?: string[];
  priority?: number | null;
}

/** Save the editable properties from the detail inspector in one local write. */
export async function updateTask(id: string, fields: TaskUpdateFields): Promise<void> {
  const title = fields.title?.trim();
  if (fields.tags) await ensureTags(normalizeTags(fields.tags));
  await db.execute(
    `UPDATE tasks
       SET title = COALESCE(?, title),
           notes = ?,
           due_at = ?,
           category = ?,
           tags = COALESCE(?, tags),
           priority = ?,
           updated_at = ?
     WHERE id = ?`,
    [
     title || null,
     fields.notes ?? null,
     fields.due_at ?? null,
     fields.category ?? null,
     fields.tags ? encodeTags(fields.tags) ?? '[]' : null,
     fields.priority ?? null,
     new Date().toISOString(),
     id
    ]
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
  await db.execute(`UPDATE tasks SET status = 'cancelled', updated_at = ? WHERE id = ?`, [
    new Date().toISOString(),
    id
  ]);
}

export async function setDone(id: string, done: boolean): Promise<void> {
  const now = new Date().toISOString();
  await db.execute(
    `UPDATE tasks SET status = ?, completed_at = ?, updated_at = ? WHERE id = ?`,
    [done ? 'done' : 'active', done ? now : null, now, id]
  );
}

export async function addTaskComment(taskId: string, body: string): Promise<void> {
  const token = getToken();
  if (!token) throw new Error('Not signed in.');
  const requestId = crypto.randomUUID();
  const res = await fetch(`${config.backendUrl}/api/tasks/${taskId}/comments`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ request_id: requestId, body }),
  });
  const payload = await res.json().catch(() => ({})) as { ok?: boolean; error?: string };
  if (!res.ok || !payload.ok) throw new Error(payload.error ?? `comment failed (${res.status})`);
}
