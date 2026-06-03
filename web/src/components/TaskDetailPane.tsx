import { useEffect, useMemo, useState } from 'react';
import { useQuery } from '@powersync/react';
import type { TaskEventRecord, TaskRecord } from '../powersync/schema';
import { confirm, reject, setDone, updateTask } from '../lib/tasks';
import { decodeTags } from '../lib/tags';
import { formatDue } from '../lib/format';
import { DueEditor } from './DueEditor';
import { TagEditor } from './TagChips';

const CATEGORIES = ['engineering', 'leadership', 'home', 'errands', 'health', 'finance', 'personal', 'inbox'];

function eventIcon(event: TaskEventRecord): string {
  if (event.actor === 'worker' || event.actor === 'agent') return '◇';
  if (event.event_type === 'completed') return '✓';
  if (event.event_type === 'captured') return '⌁';
  if (event.event_type === 'confirmed') return '→';
  return '•';
}

function eventTime(value: string | null): string {
  if (!value) return '';
  const d = new Date(value);
  const today = d.toDateString() === new Date().toDateString();
  return today
    ? d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
    : d.toLocaleDateString([], { day: 'numeric', month: 'short' });
}

function confidence(event: TaskEventRecord): string | null {
  if (!event.metadata) return null;
  try {
    const parsed = JSON.parse(event.metadata) as { confidence?: unknown };
    return typeof parsed.confidence === 'number' ? `${Math.round(parsed.confidence * 100)}%` : null;
  } catch {
    return null;
  }
}

export function TaskDetailPane({
  task,
  onClose,
}: {
  task: TaskRecord | null;
  onClose: () => void;
}) {
  const [title, setTitle] = useState('');
  const [notes, setNotes] = useState('');
  const [due, setDue] = useState<string | null>(null);
  const [category, setCategory] = useState<string | null>(null);
  const [priority, setPriority] = useState<number | null>(null);
  const [tags, setTags] = useState<string[]>([]);
  const [dirty, setDirty] = useState(false);
  const [saving, setSaving] = useState(false);

  const taskId = task?.id ?? '';
  const { data: events } = useQuery<TaskEventRecord>(
    task ? `SELECT * FROM task_events WHERE task_id = ? ORDER BY created_at DESC, id DESC LIMIT 80` : `SELECT * FROM task_events WHERE 0`,
    task ? [task.id] : []
  );

  useEffect(() => {
    if (!task) return;
    setTitle(task.title ?? '');
    setNotes(task.notes ?? '');
    setDue(task.due_at ?? null);
    setCategory(task.category ?? task.suggested_category ?? null);
    setPriority(task.priority ?? null);
    setTags(decodeTags(task.tags));
    setDirty(false);
  }, [taskId, task]);

  const isDone = task?.status === 'done';
  const isProposed = task?.status === 'proposed';
  const suggestedDue = task?.suggested_due_at ?? null;
  const suggestedCategory = task?.suggested_category ?? null;

  const sortedEvents = useMemo(() => events ?? [], [events]);

  if (!task) {
    return (
      <aside className="detail-pane detail-empty">
        <div className="detail-orb">⌁</div>
        <h2>Select a task</h2>
        <p>Open any item to inspect its structure, edit properties, and watch AI work land in the history.</p>
      </aside>
    );
  }

  async function save() {
    if (!task) return;
    setSaving(true);
    try {
      await updateTask(task.id, {
        title,
        notes: notes.trim() ? notes : null,
        due_at: due,
        category,
        tags,
        priority,
      });
      setDirty(false);
    } finally {
      setSaving(false);
    }
  }

  async function confirmFromPane() {
    if (!task) return;
    setSaving(true);
    try {
      await confirm(task.id, {
        title,
        notes: notes.trim() ? notes : null,
        due_at: due,
        category,
        tags,
        priority,
      });
      setDirty(false);
    } finally {
      setSaving(false);
    }
  }

  return (
    <aside
      className="detail-pane"
      onKeyDown={(e) => {
        if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') void (isProposed ? confirmFromPane() : save());
      }}
    >
      <div className="detail-topline">
        <span className={`detail-state detail-state-${task.status}`}>{task.status}</span>
        <button className="detail-close" type="button" onClick={onClose} aria-label="Close task details">×</button>
      </div>

      <textarea
        className="detail-title"
        value={title}
        rows={2}
        onChange={(e) => { setTitle(e.target.value); setDirty(true); }}
      />

      <div className="detail-actions">
        {isProposed ? (
          <>
            <button className="primary detail-primary" onClick={() => void confirmFromPane()} disabled={saving}>
              Confirm structure
            </button>
            <button className="ghost" onClick={() => void reject(task.id)} disabled={saving}>
              Reject
            </button>
          </>
        ) : (
          <>
            <button className="primary detail-primary" onClick={() => void save()} disabled={!dirty || saving}>
              {saving ? 'Saving…' : dirty ? 'Save changes' : 'Saved'}
            </button>
            <button className="ghost" onClick={() => void setDone(task.id, !isDone)}>
              {isDone ? 'Reopen' : 'Mark done'}
            </button>
          </>
        )}
      </div>

      <section className="detail-section">
        <h3>Properties</h3>
        <label className="detail-field">
          <span>Due</span>
          <div>
            {(suggestedDue || suggestedCategory) && (
              <p className="detail-suggestion">
                AI suggests {suggestedCategory ?? 'no category'}{suggestedDue ? ` · ${formatDue(suggestedDue)}` : ''}
              </p>
            )}
            <DueEditor value={due} onChange={(iso) => { setDue(iso); setDirty(true); }} />
          </div>
        </label>
        <label className="detail-field">
          <span>Category</span>
          <select value={category ?? ''} onChange={(e) => { setCategory(e.target.value || null); setDirty(true); }}>
            <option value="">None</option>
            {CATEGORIES.map((c) => <option value={c} key={c}>{c}</option>)}
          </select>
        </label>
        <label className="detail-field">
          <span>Priority</span>
          <select value={priority ?? ''} onChange={(e) => { setPriority(e.target.value ? Number(e.target.value) : null); setDirty(true); }}>
            <option value="">None</option>
            <option value="0">P0 · immediate</option>
            <option value="1">P1 · important</option>
            <option value="2">P2 · normal</option>
            <option value="3">P3 · someday</option>
            <option value="4">P4 · reference</option>
          </select>
        </label>
        <label className="detail-field">
          <span>Tags</span>
          <TagEditor tags={tags} onChange={(next) => { setTags(next); setDirty(true); }} />
        </label>
      </section>

      <section className="detail-section">
        <h3>Expansion</h3>
        <textarea
          className="detail-notes"
          placeholder="Add context, acceptance notes, links, or the next concrete action…"
          value={notes}
          onChange={(e) => { setNotes(e.target.value); setDirty(true); }}
        />
      </section>

      <section className="detail-section detail-history">
        <h3>AI + activity history</h3>
        {sortedEvents.length === 0 ? (
          <p className="history-empty">No synced history yet. Capture, confirmation, edits and AI updates appear here.</p>
        ) : (
          <div className="timeline">
            {sortedEvents.map((event) => (
              <article className={`timeline-event actor-${event.actor}`} key={event.id}>
                <span className="timeline-icon">{eventIcon(event)}</span>
                <div>
                  <div className="timeline-head">
                    <strong>{event.title}</strong>
                    <span>{confidence(event) ?? event.actor}</span>
                    <time>{eventTime(event.created_at)}</time>
                  </div>
                  {event.body && <p>{event.body}</p>}
                </div>
              </article>
            ))}
          </div>
        )}
      </section>
    </aside>
  );
}
