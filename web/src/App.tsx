import { useState } from 'react';
import { useStatus, useQuery } from '@powersync/react';
import type { TaskRecord } from './powersync/schema';
import { CaptureBar } from './components/CaptureBar';
import { ConfirmCard } from './components/ConfirmCard';
import { TaskRow } from './components/TaskRow';
import { TagManager } from './components/TagManager';

export default function App() {
  const status = useStatus();
  const [showTags, setShowTags] = useState(false);

  const { data: proposed } = useQuery<TaskRecord>(
    `SELECT * FROM tasks WHERE status = 'proposed' ORDER BY created_at DESC`
  );
  const { data: active } = useQuery<TaskRecord>(
    `SELECT * FROM tasks WHERE status IN ('confirmed','active') ORDER BY (due_at IS NULL), due_at ASC, created_at DESC`
  );
  const { data: done } = useQuery<TaskRecord>(
    `SELECT * FROM tasks WHERE status = 'done' ORDER BY completed_at DESC LIMIT 20`
  );

  return (
    <div className="app">
      <header>
        <h1>Capture</h1>
        <button className="tags-toggle" onClick={() => setShowTags((s) => !s)}>
          {showTags ? 'Close tags' : 'Manage tags'}
        </button>
        <span className={`sync ${status.connected ? 'on' : 'off'}`}>
          {status.connected ? 'synced' : 'offline'}
        </span>
      </header>

      <CaptureBar />

      {showTags && (
        <section>
          <h2>Tags</h2>
          <TagManager />
        </section>
      )}

      {proposed.length > 0 && (
        <section>
          <h2>Needs confirming · {proposed.length}</h2>
          <div className="cards">
            {proposed.map((t) => (
              <ConfirmCard key={t.id} task={t} />
            ))}
          </div>
        </section>
      )}

      <section>
        <h2>Active · {active.length}</h2>
        <div className="rows">
          {active.map((t) => (
            <TaskRow key={t.id} task={t} />
          ))}
          {active.length === 0 && <p className="empty">Nothing active yet.</p>}
        </div>
      </section>

      {done.length > 0 && (
        <section>
          <h2>Done</h2>
          <div className="rows">
            {done.map((t) => (
              <TaskRow key={t.id} task={t} />
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
