import { useState } from 'react';
import { useQuery } from '@powersync/react';
import type { CategoryRecord } from '../powersync/schema';
import { DEFAULT_CATEGORIES, createCategory, deleteCategory, recolorCategory, renameCategory } from '../lib/categories';
import { TAG_COLORS, tagKey } from '../lib/tags';

export function CategoryManager() {
  const { data: categories } = useQuery<CategoryRecord>(`SELECT * FROM categories ORDER BY name COLLATE NOCASE ASC`);
  const [newName, setNewName] = useState('');
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editValue, setEditValue] = useState('');
  const existing = new Set(categories.map((c) => tagKey(c.name ?? '')));
  const missingDefaults = DEFAULT_CATEGORIES.filter((name) => !existing.has(tagKey(name)));

  function addCategory(name = newName) {
    const n = name.trim();
    if (!n) return;
    setNewName('');
    void createCategory(n);
  }

  function commitRename(id: string) {
    const v = editValue.trim();
    setEditingId(null);
    if (v) void renameCategory(id, v);
  }

  return (
    <div className="tag-manager category-manager">
      <div className="tag-manager-add">
        <input
          value={newName}
          placeholder="New category…"
          onChange={(e) => setNewName(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              addCategory();
            }
          }}
        />
        <button onClick={() => addCategory()} disabled={!newName.trim()}>
          Add
        </button>
      </div>

      {missingDefaults.length > 0 && (
        <div className="category-seeds">
          {missingDefaults.map((name) => (
            <button key={name} onClick={() => addCategory(name)}>
              + {name}
            </button>
          ))}
        </div>
      )}

      <div className="tag-manager-list">
        {categories.map((c) => (
          <div className="tag-manager-row" key={c.id}>
            <span className="tag-dot" style={{ background: c.color ?? '#9BA1A6' }} />
            {editingId === c.id ? (
              <input
                autoFocus
                value={editValue}
                onChange={(e) => setEditValue(e.target.value)}
                onBlur={() => commitRename(c.id)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') commitRename(c.id);
                  if (e.key === 'Escape') setEditingId(null);
                }}
              />
            ) : (
              <button
                className="tag-manager-name"
                onClick={() => {
                  setEditingId(c.id);
                  setEditValue(c.name ?? '');
                }}
              >
                {c.name}
              </button>
            )}

            <div className="tag-swatches">
              {TAG_COLORS.map((color) => (
                <button
                  key={color}
                  className={`tag-swatch ${c.color === color ? 'sel' : ''}`}
                  style={{ background: color }}
                  title={color}
                  onClick={() => void recolorCategory(c.id, color)}
                />
              ))}
            </div>

            <button className="tag-del" title="Delete category" onClick={() => void deleteCategory(c.id)}>
              ×
            </button>
          </div>
        ))}
        {categories.length === 0 && <p className="empty">No categories yet. Add the defaults or create your own vocabulary.</p>}
      </div>
    </div>
  );
}
