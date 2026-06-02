import { useEffect, useRef, useState } from 'react';
import type { TaskRecord } from '../powersync/schema';
import { confirm, reject } from '../lib/tasks';
import { formatDue } from '../lib/format';

const CATEGORIES = ['work', 'errands', 'health', 'finance', 'home', 'social', 'inbox'];

// A proposed item awaiting the mandatory quick human confirmation.
// Pre-filled with on-device suggestions; Enter accepts, Esc rejects.
export function ConfirmCard({ task }: { task: TaskRecord }) {
  const [title, setTitle] = useState(task.title ?? '');
  const [due, setDue] = useState<string | null>(task.suggested_due_at ?? null);
  const [category, setCategory] = useState<string | null>(task.suggested_category ?? null);
  const ref = useRef<HTMLDivElement>(null);

  // Keep suggestions live until the user touches a field (they arrive asynchronously).
  const [touchedDue, setTouchedDue] = useState(false);
  const [touchedCat, setTouchedCat] = useState(false);
  useEffect(() => {
    if (!touchedDue) setDue(task.suggested_due_at ?? null);
    if (!touchedCat) setCategory(task.suggested_category ?? null);
  }, [task.suggested_due_at, task.suggested_category, touchedDue, touchedCat]);

  function accept() {
    void confirm(task.id, { title, due_at: due, category });
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
        <input
          type="datetime-local"
          value={due ? toLocalInput(due) : ''}
          onChange={(e) => {
            setTouchedDue(true);
            setDue(e.target.value ? new Date(e.target.value).toISOString() : null);
          }}
        />
      </div>

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

      <div className="card-actions">
        <button className="primary" onClick={accept}>
          Confirm
        </button>
        <button className="ghost" onClick={() => void reject(task.id)}>
          Reject
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

function toLocalInput(iso: string): string {
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(
    d.getMinutes()
  )}`;
}
