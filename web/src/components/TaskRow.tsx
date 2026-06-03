import type { TaskRecord } from '../powersync/schema';
import { setDone } from '../lib/tasks';
import { decodeTags } from '../lib/tags';
import { formatDue } from '../lib/format';
import { TagChips } from './TagChips';

export function TaskRow({ task }: { task: TaskRecord }) {
  const done = task.status === 'done';
  const tags = decodeTags(task.tags);
  return (
    <div className={`row ${done ? 'row-done' : ''}`}>
      <input
        type="checkbox"
        checked={done}
        onChange={(e) => void setDone(task.id, e.target.checked)}
      />
      <span className="row-title">{task.title}</span>
      {task.category && <span className="tag">{task.category}</span>}
      <TagChips tags={tags} />
      {task.due_at && <span className="row-due">{formatDue(task.due_at)}</span>}
    </div>
  );
}
