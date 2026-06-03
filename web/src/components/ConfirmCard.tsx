import { useEffect, useRef, useState } from 'react';
import type { TaskRecord } from '../powersync/schema';
import { confirm, reject } from '../lib/tasks';
import { decodeTags } from '../lib/tags';
import { formatDue } from '../lib/format';
import { TagEditor } from './TagChips';
import { DueEditor } from './DueEditor';

const CATEGORIES = ['engineering', 'leadership', 'home', 'errands', 'health', 'finance', 'personal', 'inbox'];

// A proposed item awaiting the mandatory quick human confirmation.
// Pre-filled with on-device suggestions; Enter accepts, Esc rejects.
export function ConfirmCard({ task }: { task: TaskRecord }) {
  const [title, setTitle] = useState(task.title ?? '');
  const [due, setDue] = useState<string | null>(task.suggested_due_at ?? null);
  const [category, setCategory] = useState<string | null>(task.suggested_category ?? null);
  const [tags, setTags] = useState<string[]>(decodeTags(task.tags));
  const ref = useRef<HTMLDivElement>(null);

  // Keep suggestions live until the user touches a field (they arrive asynchronously).
  const [touchedDue, setTouchedDue] = useState(false);
  const [touchedCat, setTouchedCat] = useState(false);
  useEffect(() => {
    if (!touchedDue) setDue(task.suggested_due_at ?? null);
    if (!touchedCat) setCategory(task.suggested_category ?? null);
  }, [task.suggested_due_at, task.suggested_category, touchedDue, touchedCat]);

  function accept() {
    void confirm(task.id, { title, due_at: due, category, tags });
  }

  return (
    <div
      className="card"
      ref={ref}
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === 'Enter' && (e.metaKey || e.target === ref.current)) accept();
        if (e.key === 'Escape') void reject(task.id);
      }}
    >
      <input className="card-title" value={title} onChange={(e) => setTitle(e.target.value)} />

      <div className="card-row">
        <label>Due</label>
        <span className="due">{due ? formatDue(due) : 'none'}</span>
      </div>
      <DueEditor
        value={due}
        onChange={(iso) => {
          setTouchedDue(true);
          setDue(iso);
        }}
      />

      <div className="card-row chips">
        {CATEGORIES.map((c) => (
          <button
            key={c}
            className={`chip ${category === c ? 'chip-on' : ''}`}
            onClick={() => {
              setTouchedCat(true);
              setCategory(c);
            }}
          >
            {c}
          </button>
        ))}
      </div>

      <div className="card-row">
        <label>Tags</label>
        <TagEditor tags={tags} onChange={setTags} />
      </div>

      <div className="card-actions">
        <button className="primary" onClick={accept}>
          Confirm <span className="kbd">⏎</span>
        </button>
        <button className="ghost" onClick={() => void reject(task.id)}>
          Reject <span className="kbd">esc</span>
        </button>
        {task.suggestion_source && (
          <span className="hint">
            suggested {Math.round((task.suggestion_confidence ?? 0) * 100)}%
          </span>
        )}
      </div>
    </div>
  );
}

