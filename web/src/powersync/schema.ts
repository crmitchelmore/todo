import { column, Schema, Table } from '@powersync/web';

// Client-side SQLite schema (mirrors Postgres public.tasks). `id` is implicit.
// Timestamps are stored as ISO-8601 text; PowerSync column types are text/integer/real only.
const tasks = new Table(
  {
    owner_id: column.text,
    title: column.text,
    notes: column.text,
    status: column.text,
    category: column.text,
    tags: column.text,
    due_at: column.text,
    priority: column.integer,
    suggested_due_at: column.text,
    suggested_category: column.text,
    suggestion_confidence: column.real,
    suggestion_source: column.text,
    source: column.text,
    created_at: column.text,
    updated_at: column.text,
    confirmed_at: column.text,
    completed_at: column.text
  },
  { indexes: { by_status: ['status', 'created_at'] } }
);

const tags = new Table(
  {
    owner_id: column.text,
    name: column.text,
    color: column.text,
    created_at: column.text,
    updated_at: column.text
  },
  { indexes: {} }
);

const task_events = new Table(
  {
    owner_id: column.text,
    task_id: column.text,
    actor: column.text,
    event_type: column.text,
    title: column.text,
    body: column.text,
    metadata: column.text,
    created_at: column.text
  },
  { indexes: { by_task_created: ['task_id', 'created_at'] } }
);

export const AppSchema = new Schema({ tasks, tags, task_events });

export type Database = (typeof AppSchema)['types'];
export type TaskRecord = Database['tasks'];
export type TagRecord = Database['tags'];
export type TaskEventRecord = Database['task_events'];
