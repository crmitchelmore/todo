import { column, Schema, Table } from '@powersync/web';

// Client-side SQLite schema (mirrors Postgres public.tasks). `id` is implicit.
// Timestamps are stored as ISO-8601 text; PowerSync column types are text/integer/real only.
const tasks = new Table(
  {
    owner_id: column.text,
    parent_task_id: column.text,
    title: column.text,
    notes: column.text,
    status: column.text,
    category: column.text,
    tags: column.text,
    due_at: column.text,
    priority: column.integer,
    github_repo: column.text,
    github_url: column.text,
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
  { indexes: { by_status: ['status', 'created_at'], by_parent: ['parent_task_id', 'status', 'created_at'] } }
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

const categories = new Table(
  {
    owner_id: column.text,
    name: column.text,
    color: column.text,
    created_at: column.text,
    updated_at: column.text
  },
  { indexes: {} }
);

const categorisation_rules = new Table(
  {
    owner_id: column.text,
    title: column.text,
    instructions: column.text,
    category: column.text,
    tags: column.text,
    enabled: column.integer,
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

const task_attachments = new Table(
  {
    owner_id: column.text,
    task_id: column.text,
    filename: column.text,
    mime_type: column.text,
    byte_size: column.integer,
    preview_data_url: column.text,
    created_at: column.text
  },
  { indexes: { by_task_created: ['task_id', 'created_at'] } }
);

const agent_proposals = new Table(
  {
    owner_id: column.text,
    task_id: column.text,
    proposal_type: column.text,
    status: column.text,
    title: column.text,
    body: column.text,
    payload: column.text,
    provenance: column.text,
    confidence: column.real,
    source: column.text,
    created_at: column.text,
    updated_at: column.text,
    decided_at: column.text,
    applied_at: column.text
  },
  { indexes: { by_status: ['status', 'created_at'], by_task_status: ['task_id', 'status'] } }
);

export const AppSchema = new Schema({ tasks, tags, categories, categorisation_rules, task_events, task_attachments, agent_proposals });

export type Database = (typeof AppSchema)['types'];
export type TaskRecord = Database['tasks'];
export type TagRecord = Database['tags'];
export type CategoryRecord = Database['categories'];
export type CategorisationRuleRecord = Database['categorisation_rules'];
export type TaskEventRecord = Database['task_events'];
export type TaskAttachmentRecord = Database['task_attachments'];
export type AgentProposalRecord = Database['agent_proposals'];
