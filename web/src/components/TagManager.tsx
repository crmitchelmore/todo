import { useState } from 'react';
import { useQuery } from '@powersync/react';
import type { TagRecord } from '../powersync/schema';
import { TAG_COLORS, createTag, deleteTag, recolorTag, renameTag } from '../lib/tags';

// Manage the user's tag set: add, rename, recolour, delete. "Projects" are just tags.
export function TagManager() {
  const { data: tags } = useQuery<TagRecord>(`SELECT * FROM tags ORDER BY name COLLATE NOCASE ASC`);
  const [newName, setNewName] = useState('');
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editValue, setEditValue] = useState('');

  function addTag() {
    const n = newName.trim();
    if (!n) return;
    setNewName('');
    void createTag(n);
  }

  function commitRename(id: string) {
    const v = editValue.trim();
    setEditingId(null);
    if (v) void renameTag(id, v);
  }

  return (
    <div className="tag-manager">
      <div className="tag-manager-add">
        <input
          value={newName}
          placeholder="New tag…"
          onChange={(e) => setNewName(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              addTag();
            }
          }}
        />
        <button onClick={addTag} disabled={!newName.trim()}>
          Add
        </button>
      </div>

      <div className="tag-manager-list">
        {tags.map((t) => (
          <div className="tag-manager-row" key={t.id}>
            <span className="tag-dot" style={{ background: t.color ?? '#9BA1A6' }} />
            {editingId === t.id ? (
              <input
                autoFocus
                value={editValue}
                onChange={(e) => setEditValue(e.target.value)}
                onBlur={() => commitRename(t.id)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') commitRename(t.id);
                  if (e.key === 'Escape') setEditingId(null);
                }}
              />
            ) : (
              <button
                className="tag-manager-name"
                onClick={() => {
                  setEditingId(t.id);
                  setEditValue(t.name ?? '');
                }}
              >
                {t.name}
              </button>
            )}

            <div className="tag-swatches">
              {TAG_COLORS.map((c) => (
                <button
                  key={c}
                  className={`tag-swatch ${t.color === c ? 'sel' : ''}`}
                  style={{ background: c }}
                  title={c}
                  onClick={() => void recolorTag(t.id, c)}
                />
              ))}
            </div>

            <button className="tag-del" title="Delete tag" onClick={() => void deleteTag(t.id)}>
              ×
            </button>
          </div>
        ))}
        {tags.length === 0 && <p className="empty">No tags yet. Add one, or paste a nested list.</p>}
      </div>
    </div>
  );
}
