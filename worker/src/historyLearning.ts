export type CategoryHints = Record<string, string[]>;

export interface HistoricalTask {
  title: string;
  category: string | null;
}

const STOPWORDS = new Set([
  'about', 'after', 'again', 'before', 'could', 'from', 'have', 'into', 'need', 'next',
  'that', 'the', 'this', 'todo', 'with', 'work', 'would', 'your'
]);

function tokens(text: string): string[] {
  return text
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .map((t) => t.trim())
    .filter((t) => t.length >= 3 && !STOPWORDS.has(t));
}

/**
 * Learn a small, deterministic hint profile from the user's already-confirmed tasks.
 * This is intentionally conservative: it proposes extra category keywords only, never mutates
 * history or changes final task structure without the normal human confirmation.
 */
export function learnCategoryHints(history: readonly HistoricalTask[], maxPerCategory = 24): CategoryHints {
  const counts = new Map<string, Map<string, number>>();
  for (const task of history) {
    if (!task.category) continue;
    const category = task.category.toLowerCase();
    const categoryCounts = counts.get(category) ?? new Map<string, number>();
    for (const token of new Set(tokens(task.title))) {
      categoryCounts.set(token, (categoryCounts.get(token) ?? 0) + 1);
    }
    counts.set(category, categoryCounts);
  }

  const hints: CategoryHints = {};
  for (const [category, categoryCounts] of counts) {
    const ranked = [...categoryCounts.entries()]
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
      .slice(0, maxPerCategory)
      .map(([token]) => token);
    if (ranked.length > 0) hints[category] = ranked;
  }
  return hints;
}
