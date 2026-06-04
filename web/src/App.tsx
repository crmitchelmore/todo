import { useEffect, useMemo, useState } from 'react';
import { useStatus, useQuery } from '@powersync/react';
import type { AgentProposalRecord, TaskRecord } from './powersync/schema';
import { CaptureBar } from './components/CaptureBar';
import { ConfirmCard } from './components/ConfirmCard';
import { TaskRow } from './components/TaskRow';
import { TaskDetailPane } from './components/TaskDetailPane';
import { TagManager } from './components/TagManager';
import { TagFilter } from './components/TagFilter';
import { SettingsPanel } from './components/SettingsPanel';
import { dateBucket, type DateBucketKey } from './lib/dates';
import { decodeTags, tagKey } from './lib/tags';
import { signOut } from './lib/auth';
import { clearActiveUser } from './powersync/db';

/** Sign out and wipe local data so the next account starts clean. */
async function handleSignOut(): Promise<void> {
  await signOut();
  await clearActiveUser();
}

/** AND/intersection: a task matches only if it carries every selected tag. */
function matchesTags(task: TaskRecord, selected: string[]): boolean {
  if (selected.length === 0) return true;
  const have = new Set(decodeTags(task.tags).map(tagKey));
  return selected.every((s) => have.has(tagKey(s)));
}

export default function App() {
  const status = useStatus();
  const [showTags, setShowTags] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [filter, setFilter] = useState<string[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const { data: proposed } = useQuery<TaskRecord>(
    `SELECT * FROM tasks WHERE status = 'proposed' ORDER BY created_at DESC`
  );
  const { data: active } = useQuery<TaskRecord>(
    `SELECT * FROM tasks WHERE status IN ('confirmed','active') ORDER BY (due_at IS NULL), due_at ASC, created_at DESC`
  );
  const { data: done } = useQuery<TaskRecord>(
    `SELECT * FROM tasks WHERE status = 'done' ORDER BY completed_at DESC LIMIT 20`
  );
  const { data: pendingProposals } = useQuery<AgentProposalRecord>(
    `SELECT * FROM agent_proposals
      WHERE status = 'pending' AND task_id IS NOT NULL
      ORDER BY created_at DESC`
  );

  const filteredActive = useMemo(() => active.filter((t) => matchesTags(t, filter)), [active, filter]);
  const filteredDone = useMemo(() => done.filter((t) => matchesTags(t, filter)), [done, filter]);
  const allVisibleTasks = useMemo(
    () => [...proposed, ...filteredActive, ...filteredDone],
    [proposed, filteredActive, filteredDone]
  );
  const selectedTask = useMemo(
    () => allVisibleTasks.find((t) => t.id === selectedId) ?? null,
    [allVisibleTasks, selectedId]
  );
  const proposalByTaskId = useMemo(() => {
    const map = new Map<string, AgentProposalRecord>();
    for (const proposal of pendingProposals) {
      if (proposal.task_id && !map.has(proposal.task_id)) map.set(proposal.task_id, proposal);
    }
    return map;
  }, [pendingProposals]);

  useEffect(() => {
    if (selectedId && !selectedTask) setSelectedId(null);
  }, [selectedId, selectedTask]);

  // Group the active list by date bucket (already sorted by due_at from the query).
  const groups = useMemo(() => {
    const map = new Map<DateBucketKey, { label: string; order: number; items: TaskRecord[] }>();
    for (const t of filteredActive) {
      const b = dateBucket(t.due_at);
      const g = map.get(b.key) ?? { label: b.label, order: b.order, items: [] };
      g.items.push(t);
      map.set(b.key, g);
    }
    return [...map.values()].sort((a, b) => a.order - b.order);
  }, [filteredActive]);

  return (
    <div className={`app app-workbench ${selectedTask ? 'detail-open' : ''}`}>
      <header>
        <h1>Capture</h1>
        <span className="header-spacer" />
        <button className="tags-toggle" onClick={() => setShowTags((s) => !s)}>
          {showTags ? 'Close tags' : 'Manage tags'}
        </button>
        <button className="tags-toggle" onClick={() => setShowSettings((s) => !s)}>
          {showSettings ? 'Close settings' : 'Settings'}
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

      {showSettings && <SettingsPanel onSignOut={handleSignOut} />}

      <div className="workbench-grid">
        <main className="task-stream">
          {proposed.length > 0 && (
            <section>
              <h2>Needs confirming · {proposed.length}</h2>
              <div className="cards">
                {proposed.map((t) => (
                  <div key={t.id} className={`confirm-shell ${selectedId === t.id ? 'selected' : ''}`}>
                    <button className="open-detail" onClick={() => setSelectedId(t.id)}>
                      Inspect
                    </button>
                    <ConfirmCard task={t} proposal={proposalByTaskId.get(t.id) ?? null} />
                  </div>
                ))}
              </div>
            </section>
          )}

          <section>
            <h2>
              Active · {filteredActive.length}
              {filter.length > 0 && <span className="filtered-of"> of {active.length}</span>}
            </h2>
            <TagFilter selected={filter} onChange={setFilter} />
            <div className="groups">
              {groups.map((g) => (
                <div className="date-group" key={g.label}>
                  <h3 className={`group-head group-${g.order}`}>
                    {g.label} <span className="group-count">{g.items.length}</span>
                  </h3>
                  <div className="rows">
                    {g.items.map((t) => (
                      <TaskRow
                        key={t.id}
                        task={t}
                        selected={selectedId === t.id}
                        onSelect={(task) => setSelectedId(task.id)}
                      />
                    ))}
                  </div>
                </div>
              ))}
              {filteredActive.length === 0 && (
                <p className="empty">{filter.length > 0 ? 'No items match this filter.' : 'Nothing active yet.'}</p>
              )}
            </div>
          </section>

          {filteredDone.length > 0 && (
            <section>
              <h2>Done</h2>
              <div className="rows">
                {filteredDone.map((t) => (
                  <TaskRow
                    key={t.id}
                    task={t}
                    selected={selectedId === t.id}
                    onSelect={(task) => setSelectedId(task.id)}
                  />
                ))}
              </div>
            </section>
          )}
        </main>

        <TaskDetailPane task={selectedTask} onClose={() => setSelectedId(null)} />
      </div>
    </div>
  );
}
