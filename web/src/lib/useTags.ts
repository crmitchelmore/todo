import { useQuery } from '@powersync/react';
import type { TagRecord } from '../powersync/schema';
import { colorForTag, tagKey } from '../lib/tags';

/** Live map of tag name (lowercased) -> colour, falling back to the deterministic palette
 *  colour for names that don't yet have a metadata row. */
export function useTagColors(): (name: string) => string {
  const { data } = useQuery<TagRecord>(`SELECT name, color FROM tags`);
  const map = new Map<string, string>();
  for (const t of data) if (t.name && t.color) map.set(tagKey(t.name), t.color);
  return (name: string) => map.get(tagKey(name)) ?? colorForTag(name);
}
