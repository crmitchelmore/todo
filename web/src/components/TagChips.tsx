import { useState } from 'react';
import { useTagColors } from '../lib/useTags';

/** Inline editor for a task's tag set: shows chips, lets you remove (×) and add via input. */
export function TagEditor({ tags, onChange }: { tags: string[]; onChange: (tags: string[]) => void }) {
  const colorFor = useTagColors();
  const [draft, setDraft] = useState('');

  function add() {
    const v = draft.trim();
    setDraft('');
    if (!v) return;
    if (tags.some((t) => t.toLowerCase() === v.toLowerCase())) return;
    onChange([...tags, v]);
  }

  function remove(name: string) {
    onChange(tags.filter((t) => t !== name));
  }

  return (
    <div className="tag-editor">
      {tags.map((t) => (
        <span className="tag-chip" key={t} style={{ background: colorFor(t) }}>
          {t}
          <button className="tag-chip-x" onClick={() => remove(t)} aria-label={`remove ${t}`}>
            ×
          </button>
        </span>
      ))}
      <input
        className="tag-add-input"
        value={draft}
        placeholder="+ tag"
        onChange={(e) => setDraft(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') {
            e.preventDefault();
            add();
          }
          if (e.key === 'Backspace' && draft === '' && tags.length) {
            remove(tags[tags.length - 1]);
          }
        }}
      />
    </div>
  );
}

/** Read-only coloured chips for a task row. */
export function TagChips({ tags }: { tags: string[] }) {
  const colorFor = useTagColors();
  if (tags.length === 0) return null;
  return (
    <span className="tag-chips">
      {tags.map((t) => (
        <span className="tag-chip sm" key={t} style={{ background: colorFor(t) }}>
          {t}
        </span>
      ))}
    </span>
  );
}
