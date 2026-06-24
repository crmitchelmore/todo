import { useState } from 'react';
import { useQuery } from '@powersync/react';
import type { CategorisationRuleRecord, CategoryRecord } from '../powersync/schema';
import { createCategorisationRule, deleteCategorisationRule, updateCategorisationRule } from '../lib/categorisationRules';
import { DEFAULT_CATEGORIES } from '../lib/categories';
import { decodeTags } from '../lib/tags';

type Draft = {
  title: string;
  instructions: string;
  category: string;
  tags: string;
  enabled: boolean;
};

const emptyDraft: Draft = {
  title: '',
  instructions: '',
  category: '',
  tags: '',
  enabled: true,
};

export function CategorisationRulesManager() {
  const { data: rules } = useQuery<CategorisationRuleRecord>(
    `SELECT * FROM categorisation_rules ORDER BY enabled DESC, updated_at DESC, title COLLATE NOCASE ASC`
  );
  const { data: categories } = useQuery<CategoryRecord>(`SELECT * FROM categories ORDER BY name COLLATE NOCASE ASC`);
  const [draft, setDraft] = useState<Draft>(emptyDraft);
  const [editingId, setEditingId] = useState<string | null>(null);
  const categoryOptions = Array.from(new Set([
    ...categories.map((category) => category.name).filter((name): name is string => Boolean(name)),
    ...DEFAULT_CATEGORIES,
  ].map((name) => name.trim()).filter(Boolean))).sort((a, b) => a.localeCompare(b));

  function parseTags(value: string): string[] {
    return value.split(',').map((tag) => tag.trim()).filter(Boolean);
  }

  function edit(rule: CategorisationRuleRecord) {
    setEditingId(rule.id);
    setDraft({
      title: rule.title ?? '',
      instructions: rule.instructions ?? '',
      category: rule.category ?? '',
      tags: decodeTags(rule.tags).join(', '),
      enabled: (rule.enabled ?? 1) !== 0,
    });
  }

  async function save() {
    const input = {
      title: draft.title,
      instructions: draft.instructions,
      category: draft.category || null,
      tags: parseTags(draft.tags),
      enabled: draft.enabled,
    };
    if (editingId) {
      await updateCategorisationRule(editingId, input);
    } else {
      await createCategorisationRule(input);
    }
    setEditingId(null);
    setDraft(emptyDraft);
  }

  return (
    <div className="rules-manager">
      <div className="rule-editor">
        <input
          value={draft.title}
          maxLength={120}
          placeholder="Rule title"
          onChange={(e) => setDraft({ ...draft, title: e.target.value })}
        />
        <textarea
          value={draft.instructions}
          maxLength={1000}
          placeholder="When should this apply? Mention words, contexts, projects, people, or intent."
          onChange={(e) => setDraft({ ...draft, instructions: e.target.value })}
        />
        <div className="rule-editor-grid">
          <select value={draft.category} onChange={(e) => setDraft({ ...draft, category: e.target.value })}>
            <option value="">No category</option>
            {categoryOptions.map((category) => (
              <option value={category} key={category}>{category}</option>
            ))}
          </select>
          <input
            value={draft.tags}
            placeholder="tags, comma-separated"
            onChange={(e) => setDraft({ ...draft, tags: e.target.value })}
          />
          <label>
            <input
              type="checkbox"
              checked={draft.enabled}
              onChange={(e) => setDraft({ ...draft, enabled: e.target.checked })}
            />
            Enabled
          </label>
        </div>
        <div className="rule-actions">
          <button onClick={() => void save()} disabled={!draft.title.trim() || !draft.instructions.trim()}>
            {editingId ? 'Save rule' : 'Add rule'}
          </button>
          {editingId && <button onClick={() => { setEditingId(null); setDraft(emptyDraft); }}>Cancel</button>}
        </div>
      </div>

      <div className="rule-list">
        {rules.map((rule) => (
          <article className={`rule-row ${rule.enabled === 0 ? 'muted' : ''}`} key={rule.id}>
            <button className="rule-main" onClick={() => edit(rule)}>
              <strong>{rule.title}</strong>
              <span>{rule.instructions}</span>
              <em>
                {[rule.category, ...decodeTags(rule.tags).map((tag) => `#${tag}`)].filter(Boolean).join(' · ') || 'suggestion context only'}
              </em>
            </button>
            <button className="tag-del" title="Delete rule" onClick={() => void deleteCategorisationRule(rule.id)}>×</button>
          </article>
        ))}
        {rules.length === 0 && (
          <p className="empty">No rules yet. Add one like “wok research → errands + shopping”.</p>
        )}
      </div>
    </div>
  );
}
