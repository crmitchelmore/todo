import type { TaskRecord } from '../powersync/schema';
import { setDone } from '../lib/tasks';
import { decodeTags } from '../lib/tags';
import { formatDue } from '../lib/format';
import { TagChips } from './TagChips';
import { RowDue } from './DueEditor';

export function TaskRow({
  task,
  selected = false,
  onSelect,
}: {
  task: TaskRecord;
  selected?: boolean;
  onSelect?: (task: TaskRecord) => void;
}) {
  const done = task.status === 'done';
  const tags = decodeTags(task.tags);
  return (
    <div
      className={`row ${done ? 'row-done' : ''} ${selected ? 'row-selected' : ''}`}
      onClick={() => onSelect?.(task)}
      onKeyDown={(e) => {
        if ((e.key === 'Enter' || e.key === ' ') && onSelect) {
          e.preventDefault();
          onSelect(task);
        }
      }}
      tabIndex={onSelect ? 0 : undefined}
    >
      <input
        type="checkbox"
        checked={done}
        onClick={(e) => e.stopPropagation()}
        onChange={(e) => void setDone(task.id, e.target.checked)}
      />
      <span className="row-title">{task.title}</span>
      {task.category && <span className="tag">{task.category}</span>}
      <TagChips tags={tags} />
      {done
        ? task.due_at && <span className="row-due row-due-static">{formatDue(task.due_at)}</span>
        : <RowDue taskId={task.id} due={task.due_at ?? null} />}
    </div>
  );
}
