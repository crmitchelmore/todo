import type { TaskRecord } from '../powersync/schema';
import { setDone } from '../lib/tasks';
import { decodeTags } from '../lib/tags';
import { formatDue, formatTimestamp } from '../lib/format';
import { TagChips } from './TagChips';
import { RowDue } from './DueEditor';

export function TaskRow({
  task,
  selected = false,
  onSelect,
  readOnly = false,
  tone = 'normal',
}: {
  task: TaskRecord;
  selected?: boolean;
  onSelect?: (task: TaskRecord) => void;
  readOnly?: boolean;
  tone?: 'normal' | 'rejected';
}) {
  const done = task.status === 'done';
  const rejected = tone === 'rejected' || task.status === 'cancelled';
  const tags = decodeTags(task.tags);
  return (
    <div
      className={`row ${done ? 'row-done' : ''} ${rejected ? 'row-rejected' : ''} ${selected ? 'row-selected' : ''}`}
      onClick={() => onSelect?.(task)}
      onKeyDown={(e) => {
        if ((e.key === 'Enter' || e.key === ' ') && onSelect) {
          e.preventDefault();
          onSelect(task);
        }
      }}
      tabIndex={onSelect ? 0 : undefined}
    >
      {!readOnly && (
        <input
          type="checkbox"
          checked={done}
          onClick={(e) => e.stopPropagation()}
          onChange={(e) => void setDone(task.id, e.target.checked)}
        />
      )}
      <span className="row-title">{task.title}</span>
      {task.category && <span className="tag">{task.category}</span>}
      <TagChips tags={tags} />
      {rejected
        ? <span className="row-due row-due-static">{task.updated_at ? `Rejected ${formatTimestamp(task.updated_at)}` : 'Rejected'}</span>
        : done
          ? task.due_at && <span className="row-due row-due-static">{formatDue(task.due_at)}</span>
          : <RowDue taskId={task.id} due={task.due_at ?? null} />}
    </div>
  );
}
