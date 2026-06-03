import { useState } from 'react';
import { setDue } from '../lib/tasks';
import { formatDue } from '../lib/format';
import { PRESET_LABELS, presetDate } from '../lib/dates';

function toLocalInput(iso: string): string {
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(
    d.getMinutes()
  )}`;
}

/**
 * Inline due-date control: quick presets + a precise datetime-local picker. Used on active rows
 * (writes straight through `setDue`) and, in a controlled variant, inside the confirm card.
 */
export function DueEditor({
  value,
  onChange
}: {
  value: string | null;
  onChange: (iso: string | null) => void;
}) {
  return (
    <div className="due-editor">
      <div className="due-presets">
        {PRESET_LABELS.map(({ preset, label }) => (
          <button key={preset} className="chip" onClick={() => onChange(presetDate(preset))}>
            {label}
          </button>
        ))}
        {value && (
          <button className="chip chip-clear" onClick={() => onChange(null)}>
            Clear
          </button>
        )}
      </div>
      <input
        type="datetime-local"
        value={value ? toLocalInput(value) : ''}
        onChange={(e) => onChange(e.target.value ? new Date(e.target.value).toISOString() : null)}
      />
    </div>
  );
}

/** The due chip on an active row; click to reveal the editor, which persists via setDue. */
export function RowDue({ taskId, due }: { taskId: string; due: string | null }) {
  const [open, setOpen] = useState(false);
  return (
    <span className="row-due-wrap">
      <button className={`row-due ${due ? '' : 'row-due-empty'}`} onClick={() => setOpen((o) => !o)}>
        {due ? formatDue(due) : '+ date'}
      </button>
      {open && (
        <div className="due-popover">
          <DueEditor
            value={due}
            onChange={(iso) => {
              void setDue(taskId, iso);
              setOpen(false);
            }}
          />
        </div>
      )}
    </span>
  );
}
