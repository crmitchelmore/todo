import { useQuery } from '@powersync/react';
import type { TagRecord } from '../powersync/schema';
import { useTagColors } from '../lib/useTags';

/**
 * Multi-select tag filter ("slice by tag or multiple tags"). AND/intersection semantics:
 * selecting more tags narrows the list to items carrying ALL selected tags. Empty = show all.
 */
export function TagFilter({
  selected,
  onChange
}: {
  selected: string[];
  onChange: (tags: string[]) => void;
}) {
  const { data: tags } = useQuery<TagRecord>(`SELECT * FROM tags ORDER BY name COLLATE NOCASE ASC`);
  const colorFor = useTagColors();
  if (tags.length === 0) return null;

  const toggle = (name: string) => {
    const key = name.toLowerCase();
    const has = selected.some((s) => s.toLowerCase() === key);
    onChange(has ? selected.filter((s) => s.toLowerCase() !== key) : [...selected, name]);
  };

  return (
    <div className="tag-filter">
      <span className="tag-filter-label">Filter</span>
      {tags.map((t) => {
        if (!t.name) return null;
        const name = t.name;
        const on = selected.some((s) => s.toLowerCase() === name.toLowerCase());
        return (
          <button
            key={t.id}
            className={`filter-chip ${on ? 'on' : ''}`}
            style={on ? { background: colorFor(name), borderColor: colorFor(name) } : undefined}
            onClick={() => toggle(name)}
          >
            {name}
          </button>
        );
      })}
      {selected.length > 0 && (
        <button className="filter-chip clear" onClick={() => onChange([])}>
          Clear
        </button>
      )}
    </div>
  );
}
