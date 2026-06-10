import { useState } from 'react';
import { useQuery } from '@powersync/react';
import type { UserMemoryRecord } from '../powersync/schema';
import { createUserMemory, setUserMemoryStatus, updateUserMemory, type UserMemoryStatus } from '../lib/userMemories';
import { decodeTags } from '../lib/tags';

type Draft = {
  content: string;
  domain: string;
  tags: string;
  expires_at: string;
  status: UserMemoryStatus;
};

const emptyDraft: Draft = { content: '', domain: '', tags: '', expires_at: '', status: 'active' };

export function UserMemoryManager() {
  const { data: memories } = useQuery<UserMemoryRecord>(
    `SELECT * FROM user_memories WHERE status <> 'deleted' ORDER BY status ASC, updated_at DESC, content COLLATE NOCASE ASC`
  );
  const [draft, setDraft] = useState<Draft>(emptyDraft);
  const [editingId, setEditingId] = useState<string | null>(null);

  function parseTags(value: string): string[] {
    return value.split(',').map((tag) => tag.trim()).filter(Boolean);
  }

  function edit(memory: UserMemoryRecord) {
    setEditingId(memory.id);
    setDraft({
      content: memory.content ?? '',
      domain: memory.domain ?? '',
      tags: decodeTags(memory.tags).join(', '),
      expires_at: memory.expires_at ? memory.expires_at.slice(0, 10) : '',
      status: memory.status === 'disabled' ? 'disabled' : 'active',
    });
  }

  async function save() {
    const input = {
      content: draft.content,
      domain: draft.domain || null,
      source: 'manual' as const,
      confidence: 1,
      tags: parseTags(draft.tags),
      status: draft.status,
      expires_at: draft.expires_at ? new Date(`${draft.expires_at}T23:59:59.000Z`).toISOString() : null,
    };
    if (editingId) {
      await updateUserMemory(editingId, input);
    } else {
      await createUserMemory(input);
    }
    setEditingId(null);
    setDraft(emptyDraft);
  }

  return (
    <div className="memory-manager">
      <div className="memory-editor">
        <textarea
          value={draft.content}
          maxLength={1000}
          placeholder="Preference or fact, e.g. “For cookware I prefer buy-it-for-life quality, £80–£150, fast UK delivery, and no non-stick coatings.”"
          onChange={(event) => setDraft({ ...draft, content: event.target.value })}
        />
        <div className="memory-grid">
          <input
            value={draft.domain}
            maxLength={80}
            placeholder="domain, e.g. shopping"
            onChange={(event) => setDraft({ ...draft, domain: event.target.value })}
          />
          <input
            value={draft.tags}
            placeholder="tags, comma-separated"
            onChange={(event) => setDraft({ ...draft, tags: event.target.value })}
          />
          <input
            type="date"
            value={draft.expires_at}
            onChange={(event) => setDraft({ ...draft, expires_at: event.target.value })}
          />
          <select value={draft.status} onChange={(event) => setDraft({ ...draft, status: event.target.value as UserMemoryStatus })}>
            <option value="active">Active</option>
            <option value="disabled">Disabled</option>
          </select>
        </div>
        <div className="rule-actions">
          <button onClick={() => void save()} disabled={!draft.content.trim()}>
            {editingId ? 'Save memory' : 'Add memory'}
          </button>
          {editingId && <button onClick={() => { setEditingId(null); setDraft(emptyDraft); }}>Cancel</button>}
        </div>
      </div>

      <div className="memory-list">
        {memories.map((memory) => {
          const disabled = memory.status === 'disabled';
          const tags = decodeTags(memory.tags);
          return (
            <article className={`memory-row ${disabled ? 'muted' : ''}`} key={memory.id}>
              <button className="memory-main" onClick={() => edit(memory)}>
                <strong>{memory.domain || 'general'}</strong>
                <span>{memory.content}</span>
                <em>
                  {[memory.source, ...tags.map((tag) => `#${tag}`), memory.expires_at ? `expires ${new Date(memory.expires_at).toLocaleDateString()}` : null]
                    .filter(Boolean)
                    .join(' · ')}
                </em>
              </button>
              <button className="tag-del" onClick={() => void setUserMemoryStatus(memory.id, disabled ? 'active' : 'disabled')}>
                {disabled ? '↺' : '–'}
              </button>
              <button className="tag-del" onClick={() => void setUserMemoryStatus(memory.id, 'deleted')}>×</button>
            </article>
          );
        })}
        {memories.length === 0 && <p className="empty">No memories yet. Add facts or preferences the agent should consider.</p>}
      </div>
    </div>
  );
}
