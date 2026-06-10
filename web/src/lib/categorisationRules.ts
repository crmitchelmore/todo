import { db, ownerId } from '../powersync/db';
import { encodeTags, normalizeTags } from './tags';

export interface CategorisationRuleInput {
  title: string;
  instructions: string;
  category: string | null;
  tags: string[];
  enabled: boolean;
}

function clean(input: CategorisationRuleInput): CategorisationRuleInput | null {
  const title = input.title.trim().slice(0, 120);
  const instructions = input.instructions.trim().slice(0, 1000);
  if (!title || !instructions) return null;
  return {
    title,
    instructions,
    category: input.category?.trim().slice(0, 80) || null,
    tags: normalizeTags(input.tags).map((tag) => tag.slice(0, 80)),
    enabled: input.enabled,
  };
}

export async function createCategorisationRule(input: CategorisationRuleInput): Promise<string | null> {
  const cleaned = clean(input);
  if (!cleaned) return null;
  const id = crypto.randomUUID();
  const now = new Date().toISOString();
  await db.execute(
    `INSERT INTO categorisation_rules
       (id, owner_id, title, instructions, category, tags, enabled, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      id,
      ownerId(),
      cleaned.title,
      cleaned.instructions,
      cleaned.category,
      encodeTags(cleaned.tags),
      cleaned.enabled ? 1 : 0,
      now,
      now
    ]
  );
  return id;
}

export async function updateCategorisationRule(id: string, input: CategorisationRuleInput): Promise<void> {
  const cleaned = clean(input);
  if (!cleaned) return;
  await db.execute(
    `UPDATE categorisation_rules
        SET title = ?, instructions = ?, category = ?, tags = ?, enabled = ?, updated_at = ?
      WHERE id = ?`,
    [
      cleaned.title,
      cleaned.instructions,
      cleaned.category,
      encodeTags(cleaned.tags),
      cleaned.enabled ? 1 : 0,
      new Date().toISOString(),
      id
    ]
  );
}

export async function deleteCategorisationRule(id: string): Promise<void> {
  await db.execute(`DELETE FROM categorisation_rules WHERE id = ?`, [id]);
}
