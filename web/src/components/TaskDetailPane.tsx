import { useEffect, useMemo, useRef, useState } from 'react';
import { useQuery } from '@powersync/react';
import type { AgentProposalRecord, TaskAttachmentRecord, TaskEventRecord, TaskRecord } from '../powersync/schema';
import { requestAgentHandoff, type AgentHandoffMode } from '../lib/agentHandoff';
import { decideAgentProposal, proposalMeta } from '../lib/proposals';
import { addTaskComment, confirm, reject, setDone, updateTask } from '../lib/tasks';
import { decodeTags } from '../lib/tags';
import { formatDue } from '../lib/format';
import { DueEditor } from './DueEditor';
import { TagEditor } from './TagChips';

const CATEGORIES = ['engineering', 'leadership', 'home', 'errands', 'health', 'finance', 'personal', 'inbox'];

type TaskRollupRecord = {
  total: number;
  done: number;
  open: number;
};

type ScopedTaskEventRecord = TaskEventRecord & {
  task_title?: string | null;
  depth?: number | null;
};

type ScopedTaskAttachmentRecord = TaskAttachmentRecord & {
  task_title?: string | null;
  depth?: number | null;
};

function eventIcon(event: TaskEventRecord): string {
  if (event.event_type === 'commented') return '“';
  if (event.event_type === 'agent_requested') return '↗';
  if (event.event_type === 'agent_failed') return '!';
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

type EditableSnapshot = {
  title: string;
  notes: string;
  due: string | null;
  category: string | null;
  priority: number | null;
  tagsKey: string;
};

type TimelineDisplay = {
  title: string;
  body: string | null;
  details: Record<string, unknown> | null;
};

function snapshotFromFields(fields: {
  title: string;
  notes: string;
  due: string | null;
  category: string | null;
  priority: number | null;
  tags: string[];
}): EditableSnapshot {
  return {
    title: fields.title,
    notes: fields.notes,
    due: fields.due,
    category: fields.category,
    priority: fields.priority,
    tagsKey: JSON.stringify(fields.tags),
  };
}

function sameSnapshot(a: EditableSnapshot, b: EditableSnapshot): boolean {
  return a.title === b.title &&
    a.notes === b.notes &&
    a.due === b.due &&
    a.category === b.category &&
    a.priority === b.priority &&
    a.tagsKey === b.tagsKey;
}

function parseMetadata(value: string | null): Record<string, unknown> | null {
  if (!value) return null;
  try {
    const parsed = JSON.parse(value) as unknown;
    return typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

function semanticColumnLabel(column: string): string {
  const labels: Record<string, string> = {
    title: 'title',
    notes: 'description',
    due_at: 'due date',
    category: 'category',
    tags: 'tags',
    priority: 'priority',
    github_repo: 'GitHub repo',
    github_url: 'GitHub URL',
  };
  return labels[column] ?? column.replaceAll('_', ' ');
}

function timelineDisplay(event: TaskEventRecord): TimelineDisplay {
  const metadata = parseMetadata(event.metadata);
  const rawColumns = metadata?.changed_columns;
  const columns = Array.isArray(rawColumns)
    ? rawColumns.filter((value): value is string => typeof value === 'string')
    : [];
  const details = metadata && (columns.length > 0 || metadata.raw_changes)
    ? {
      changed_columns: columns,
      raw_changes: metadata.raw_changes ?? null,
    }
    : null;

  if (event.event_type === 'commented') {
    return { title: 'Comment', body: event.body ?? null, details };
  }
  if (event.event_type === 'updated' && event.title === 'Updated' && columns.length > 0) {
    const labels = columns.map(semanticColumnLabel);
    return {
      title: labels.length === 1 ? `${labels[0]} changed` : 'Task structure changed',
      body: labels.length === 1 ? null : labels.join(' · '),
      details,
    };
  }
  return { title: event.title ?? 'Activity', body: event.body ?? null, details };
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
  const [, setDirty] = useState(false);
  const [saving, setSaving] = useState(false);
  const [saveState, setSaveState] = useState<'saved' | 'saving' | 'dirty' | 'error'>('saved');
  const [saveError, setSaveError] = useState<string | null>(null);
  const [comment, setComment] = useState('');
  const [commentBusy, setCommentBusy] = useState(false);
  const [commentMessage, setCommentMessage] = useState<string | null>(null);
  const [handoffInstructions, setHandoffInstructions] = useState('');
  const [handoffBusy, setHandoffBusy] = useState<AgentHandoffMode | null>(null);
  const [handoffMessage, setHandoffMessage] = useState<string | null>(null);
  const savedSnapshot = useRef<EditableSnapshot | null>(null);
  const autosaveTimer = useRef<ReturnType<typeof window.setTimeout> | null>(null);

  const taskId = task?.id ?? '';
  const { data: events } = useQuery<ScopedTaskEventRecord>(
    task
      ? `
        WITH RECURSIVE descendants(id, task_title, depth) AS (
          SELECT id, title, 1 FROM tasks WHERE parent_task_id = ?
          UNION ALL
          SELECT t.id, t.title, d.depth + 1
            FROM tasks t
            JOIN descendants d ON t.parent_task_id = d.id
        ),
        root_events AS (
          SELECT
            e.id,
            e.owner_id,
            e.task_id,
            e.actor,
            e.event_type,
            e.title,
            e.body,
            e.metadata,
            e.created_at,
            NULL AS task_title,
            0 AS depth
            FROM task_events e
           WHERE e.task_id = ?
           ORDER BY e.created_at DESC, e.id DESC
           LIMIT 80
        ),
        descendant_events AS (
          SELECT
            e.id,
            e.owner_id,
            e.task_id,
            e.actor,
            e.event_type,
            e.title,
            e.body,
            e.metadata,
            e.created_at,
            d.task_title,
            d.depth
            FROM task_events e
            JOIN descendants d ON e.task_id = d.id
           ORDER BY e.created_at DESC, e.id DESC
           LIMIT 80
        )
        SELECT * FROM root_events
        UNION ALL
        SELECT * FROM descendant_events
        ORDER BY created_at DESC, id DESC
      `
      : `SELECT *, NULL AS task_title, NULL AS depth FROM task_events WHERE 0`,
    task ? [task.id, task.id] : []
  );
  const { data: rollups } = useQuery<TaskRollupRecord>(
    task
      ? `
        WITH RECURSIVE descendants(id) AS (
          SELECT id FROM tasks WHERE parent_task_id = ?
          UNION ALL
          SELECT t.id
            FROM tasks t
            JOIN descendants d ON t.parent_task_id = d.id
        )
        SELECT
          COUNT(*) AS total,
          COALESCE(SUM(CASE WHEN status = 'done' THEN 1 ELSE 0 END), 0) AS done,
          COALESCE(SUM(CASE WHEN status NOT IN ('done', 'cancelled') THEN 1 ELSE 0 END), 0) AS open
          FROM tasks
         WHERE id IN (SELECT id FROM descendants)
           AND status <> 'cancelled'
      `
      : `SELECT 0 AS total, 0 AS done, 0 AS open WHERE 0`,
    task ? [task.id] : []
  );
  const { data: attachments } = useQuery<ScopedTaskAttachmentRecord>(
    task
      ? `
        WITH RECURSIVE descendants(id, task_title, depth) AS (
          SELECT id, title, 1 FROM tasks WHERE parent_task_id = ?
          UNION ALL
          SELECT t.id, t.title, d.depth + 1
            FROM tasks t
            JOIN descendants d ON t.parent_task_id = d.id
        ),
        root_attachments AS (
          SELECT
            a.id,
            a.owner_id,
            a.task_id,
            a.filename,
            a.mime_type,
            a.byte_size,
            a.preview_data_url,
            a.created_at,
            NULL AS task_title,
            0 AS depth
            FROM task_attachments a
           WHERE a.task_id = ?
           ORDER BY a.created_at DESC, a.id DESC
           LIMIT 80
        ),
        descendant_attachments AS (
          SELECT
            a.id,
            a.owner_id,
            a.task_id,
            a.filename,
            a.mime_type,
            a.byte_size,
            a.preview_data_url,
            a.created_at,
            d.task_title,
            d.depth
            FROM task_attachments a
            JOIN descendants d ON a.task_id = d.id
           ORDER BY a.created_at DESC, a.id DESC
           LIMIT 80
        )
        SELECT * FROM root_attachments
        UNION ALL
        SELECT * FROM descendant_attachments
        ORDER BY created_at DESC, id DESC
      `
      : `SELECT *, NULL AS task_title, NULL AS depth FROM task_attachments WHERE 0`,
    task ? [task.id, task.id] : []
  );
  const { data: taskProposals } = useQuery<AgentProposalRecord>(
    task
      ? `SELECT * FROM agent_proposals
          WHERE task_id = ? AND status = 'pending'
          ORDER BY created_at DESC
          LIMIT 12`
      : `SELECT * FROM agent_proposals WHERE 0`,
    task ? [task.id] : []
  );

  useEffect(() => {
    if (!task) return;
    const nextFields = {
      title: task.title ?? '',
      notes: task.notes ?? '',
      due: task.due_at ?? null,
      category: task.category ?? task.suggested_category ?? null,
      priority: task.priority ?? null,
      tags: decodeTags(task.tags),
    };
    setTitle(nextFields.title);
    setNotes(nextFields.notes);
    setDue(nextFields.due);
    setCategory(nextFields.category);
    setPriority(nextFields.priority);
    setTags(nextFields.tags);
    savedSnapshot.current = snapshotFromFields(nextFields);
    setDirty(false);
    setSaveState('saved');
    setSaveError(null);
    setComment('');
    setCommentMessage(null);
  }, [taskId]);

  const isDone = task?.status === 'done';
  const isProposed = task?.status === 'proposed';
  const suggestedDue = task?.suggested_due_at ?? null;
  const suggestedCategory = task?.suggested_category ?? null;

  const sortedEvents = useMemo(() => events ?? [], [events]);
  const sortedAttachments = useMemo(() => attachments ?? [], [attachments]);
  const pendingTaskProposals = useMemo(() => taskProposals ?? [], [taskProposals]);
  const rollup = rollups?.[0] ?? { total: 0, done: 0, open: 0 };
  const hasSubtasks = rollup.total > 0;
  const completion = hasSubtasks ? Math.round((rollup.done / rollup.total) * 100) : 0;
  const tagsKey = useMemo(() => JSON.stringify(tags), [tags]);
  const currentSnapshot = useMemo(() => snapshotFromFields({
    title,
    notes,
    due,
    category,
    priority,
    tags,
  }), [title, notes, due, category, priority, tagsKey]);

  useEffect(() => {
    if (!task || task.status === 'proposed') return;
    const last = savedSnapshot.current;
    if (!last || sameSnapshot(last, currentSnapshot)) {
      setDirty(false);
      if (saveState !== 'saving') setSaveState('saved');
      return;
    }
    setDirty(true);
    setSaveState('dirty');
    if (autosaveTimer.current) window.clearTimeout(autosaveTimer.current);
    autosaveTimer.current = window.setTimeout(() => {
      void persistCurrent();
    }, 650);
    return () => {
      if (autosaveTimer.current) window.clearTimeout(autosaveTimer.current);
    };
  }, [taskId, task?.status, currentSnapshot]);

  if (!task) {
    return (
      <aside className="detail-pane detail-empty">
        <div className="detail-orb">⌁</div>
        <h2>Select a task</h2>
        <p>Open any item to inspect its structure, edit properties, and watch AI work land in the history.</p>
      </aside>
    );
  }

  async function persistCurrent() {
    if (!task) return;
    const snapshot = currentSnapshot;
    if (savedSnapshot.current && sameSnapshot(savedSnapshot.current, snapshot)) {
      setDirty(false);
      setSaveState('saved');
      return;
    }
    setSaving(true);
    setSaveState('saving');
    try {
      await updateTask(task.id, {
        title,
        notes: notes.trim() ? notes : null,
        due_at: due,
        category,
        tags,
        priority,
      });
      savedSnapshot.current = snapshot;
      setDirty(false);
      setSaveState('saved');
      setSaveError(null);
    } catch (err) {
      setSaveState('error');
      setSaveError(err instanceof Error ? err.message : String(err));
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
      savedSnapshot.current = currentSnapshot;
      setDirty(false);
      setSaveState('saved');
      setSaveError(null);
    } finally {
      setSaving(false);
    }
  }

  async function submitComment() {
    if (!task) return;
    const body = comment.trim();
    if (!body) return;
    setCommentBusy(true);
    setCommentMessage(null);
    try {
      await addTaskComment(task.id, body);
      setComment('');
      setCommentMessage('Comment added.');
    } catch (err) {
      setCommentMessage(err instanceof Error ? err.message : String(err));
    } finally {
      setCommentBusy(false);
    }
  }

  async function handoff(mode: AgentHandoffMode) {
    if (!task) return;
    setHandoffBusy(mode);
    setHandoffMessage(null);
    try {
      await requestAgentHandoff(task.id, mode, handoffInstructions.trim() || null);
      setHandoffInstructions('');
      setHandoffMessage(mode === 'attempt'
        ? 'Attempt requested. The agent will research first, then pause before external action.'
        : 'Research requested. Results will land in the history and briefs.');
    } catch (err) {
      setHandoffMessage(err instanceof Error ? err.message : String(err));
    } finally {
      setHandoffBusy(null);
    }
  }

  async function decideBrief(id: string, decision: 'accepted' | 'rejected') {
    setSaving(true);
    try {
      await decideAgentProposal(id, decision);
    } finally {
      setSaving(false);
    }
  }

  return (
    <aside
      className="detail-pane"
      onKeyDown={(e) => {
        if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') void (isProposed ? confirmFromPane() : persistCurrent());
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
            <span className={`autosave-state autosave-${saveState}`}>
              {saveState === 'saving' ? 'Autosaving…' : saveState === 'dirty' ? 'Autosave pending' : saveState === 'error' ? 'Autosave failed' : 'Autosaved'}
            </span>
            <button className="ghost" onClick={() => void setDone(task.id, !isDone)}>
              {isDone ? 'Reopen' : 'Mark done'}
            </button>
            {saveError && <span className="autosave-error">{saveError}</span>}
          </>
        )}
      </div>

      <section className="detail-section detail-agent-loop">
        <div className="agent-loop-head">
          <div>
            <h3>AI loop</h3>
            <p>Hand this task to the agent for one research turn, or ask it to prepare an attempted execution plan.</p>
          </div>
          <span className="agent-loop-badge">human gated</span>
        </div>
        <textarea
          className="agent-loop-input"
          value={handoffInstructions}
          onChange={(e) => setHandoffInstructions(e.target.value)}
          placeholder="Optional direction: what should the agent look for, avoid, or try first?"
          maxLength={1000}
        />
        <div className="agent-loop-actions">
          <button className="primary" type="button" disabled={handoffBusy !== null} onClick={() => void handoff('research')}>
            {handoffBusy === 'research' ? 'Requesting…' : 'Research'}
          </button>
          <button className="ghost agent-attempt" type="button" disabled={handoffBusy !== null} onClick={() => void handoff('attempt')}>
            {handoffBusy === 'attempt' ? 'Preparing…' : 'Attempt plan'}
          </button>
        </div>
        {handoffMessage && <p className="agent-loop-message">{handoffMessage}</p>}
        {pendingTaskProposals.length > 0 && (
          <div className="agent-briefs">
            {pendingTaskProposals.map((proposal) => {
              const meta = proposalMeta(proposal);
              const action = proposal.proposal_type === 'action';
              return (
                <article key={proposal.id} className={`agent-brief ${action ? 'agent-brief-action' : ''}`}>
                  <span>{proposal.source || 'agent'} · {meta.actionType.replaceAll('_', ' ')}</span>
                  <strong>{proposal.title}</strong>
                  <p>{proposal.body || 'The agent has prepared context for this task.'}</p>
                  {action ? (
                    <em>Review this in the approval queue before the agent continues.</em>
                  ) : (
                    <div className="agent-brief-actions">
                      <button className="ghost" type="button" disabled={saving} onClick={() => void decideBrief(proposal.id, 'accepted')}>
                        Archive useful
                      </button>
                      <button className="ghost" type="button" disabled={saving} onClick={() => void decideBrief(proposal.id, 'rejected')}>
                        Dismiss
                      </button>
                    </div>
                  )}
                </article>
              );
            })}
          </div>
        )}
      </section>

      {hasSubtasks && (
        <section className="detail-section detail-rollup">
          <h3>Subtasks</h3>
          <div className="rollup-summary">
            <strong>{rollup.done}/{rollup.total} complete</strong>
            <span>{rollup.open} open</span>
            <span>{completion}%</span>
          </div>
          <div className="rollup-track" aria-label={`${completion}% of subtasks complete`}>
            <span style={{ width: `${completion}%` }} />
          </div>
        </section>
      )}

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
        {task.github_repo && (
          <div className="detail-field">
            <span>GitHub</span>
            {task.github_url ? (
              <a className="github-link" href={task.github_url} target="_blank" rel="noreferrer">
                {task.github_repo}
              </a>
            ) : (
              <strong className="github-link">{task.github_repo}</strong>
            )}
          </div>
        )}
        <label className="detail-field">
          <span>Tags</span>
          <TagEditor tags={tags} onChange={(next) => { setTags(next); setDirty(true); }} />
        </label>
      </section>

      <section className="detail-section">
        <div className="detail-section-head">
          <div>
            <h3>Expansion</h3>
            {!isProposed && <p>Description autosaves. Comments are added to history.</p>}
          </div>
          {!isProposed && (
            <button
              className="ghost comment-button"
              type="button"
              disabled={commentBusy || !comment.trim()}
              onClick={() => void submitComment()}
            >
              {commentBusy ? 'Adding…' : 'Add comment'}
            </button>
          )}
        </div>
        <textarea
          className="detail-notes"
          placeholder="Add context, acceptance notes, links, or the next concrete action…"
          value={notes}
          onChange={(e) => { setNotes(e.target.value); setDirty(true); }}
        />
        {!isProposed && (
          <div className="comment-composer">
            <textarea
              className="comment-input"
              placeholder="Comment on what changed, decisions made, or evidence found…"
              value={comment}
              maxLength={2000}
              onChange={(e) => setComment(e.target.value)}
            />
            {commentMessage && <p className="comment-message">{commentMessage}</p>}
          </div>
        )}
      </section>

      <section className="detail-section detail-history">
        <h3>AI + activity history</h3>
        {sortedEvents.length === 0 && sortedAttachments.length === 0 ? (
          <p className="history-empty">No synced history yet. Capture, confirmation, edits and AI updates appear here.</p>
        ) : (
          <div className="timeline">
            {sortedAttachments.map((attachment) => (
              <article className="timeline-event actor-user timeline-attachment" key={attachment.id}>
                <span className="timeline-icon">▧</span>
                <div>
                  <div className="timeline-head">
                    <strong>Attached image</strong>
                    {(attachment.depth ?? 0) > 0 && attachment.task_title && (
                      <span className="timeline-task">{attachment.task_title}</span>
                    )}
                    <span>{attachment.mime_type}</span>
                    <time>{eventTime(attachment.created_at)}</time>
                  </div>
                  {attachment.preview_data_url && (
                    <img src={attachment.preview_data_url} alt={attachment.filename ?? 'Attached image'} />
                  )}
                </div>
              </article>
            ))}
            {sortedEvents.map((event) => {
              const display = timelineDisplay(event);
              return (
                <article className={`timeline-event actor-${event.actor} event-${event.event_type}`} key={event.id}>
                  <span className="timeline-icon">{eventIcon(event)}</span>
                  <div>
                    <div className="timeline-head">
                      <strong>{display.title}</strong>
                      {(event.depth ?? 0) > 0 && event.task_title && (
                        <span className="timeline-task">{event.task_title}</span>
                      )}
                      <span>{confidence(event) ?? event.actor}</span>
                      <time>{eventTime(event.created_at)}</time>
                    </div>
                    {display.body && <p>{display.body}</p>}
                    {display.details && (
                      <details className="timeline-raw">
                        <summary>Raw database change</summary>
                        <pre>{JSON.stringify(display.details, null, 2)}</pre>
                      </details>
                    )}
                  </div>
                </article>
              );
            })}
          </div>
        )}
      </section>
    </aside>
  );
}
