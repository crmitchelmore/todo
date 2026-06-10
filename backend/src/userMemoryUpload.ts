import type pg from 'pg';

export function normalizeUserMemoryWrite(data: Record<string, unknown>): void {
  if (!Object.hasOwn(data, 'status')) {
    delete data.deleted_at;
    return;
  }
  const status = typeof data.status === 'string' ? data.status : 'active';
  data.status = status === 'disabled' || status === 'deleted' ? status : 'active';
  if (data.status === 'deleted') {
    data.deleted_at = typeof data.deleted_at === 'string' && data.deleted_at ? data.deleted_at : new Date().toISOString();
  } else {
    data.deleted_at = null;
  }
}

export async function softDeleteUserMemory(
  client: Pick<pg.PoolClient, 'query'>,
  ownerId: string,
  id: string
): Promise<boolean> {
  const result = await client.query(
    `UPDATE public.user_memories
        SET status = 'deleted',
            deleted_at = COALESCE(deleted_at, now()),
            updated_at = now()
      WHERE id = $1 AND owner_id = $2`,
    [id, ownerId]
  );
  return (result.rowCount ?? 0) > 0;
}
