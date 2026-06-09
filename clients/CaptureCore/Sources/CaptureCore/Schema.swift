import Foundation
import PowerSync

public let TASKS_TABLE = "tasks"
public let TAGS_TABLE = "tags"
public let CATEGORIES_TABLE = "categories"
public let TASK_EVENTS_TABLE = "task_events"
public let TASK_ATTACHMENTS_TABLE = "task_attachments"
public let AGENT_PROPOSALS_TABLE = "agent_proposals"

/// Client-side SQLite schema. Mirrors Postgres `public.tasks` / `public.tags`. The `id`
/// column is auto-created by PowerSync — never declare it.
public let AppSchema = Schema(
    Table(
        name: TASKS_TABLE,
        columns: [
            .text("owner_id"),
            .text("parent_task_id"),
            .text("title"),
            .text("notes"),
            .text("status"),
            .text("category"),
            .text("tags"),               // JSON array of tag names
            .text("due_at"),
            .integer("priority"),
            .text("github_repo"),
            .text("github_url"),
            .text("suggested_due_at"),
            .text("suggested_category"),
            .real("suggestion_confidence"),
            .text("suggestion_source"),
            .text("source"),
            .text("created_at"),
            .text("updated_at"),
            .text("confirmed_at"),
            .text("completed_at")
        ],
        indexes: [
            Index(name: "by_status", columns: [IndexedColumn.ascending("status")]),
            Index(name: "by_parent", columns: [
                IndexedColumn.ascending("parent_task_id"),
                IndexedColumn.ascending("status")
            ])
        ]
    ),
    Table(
        name: TAGS_TABLE,
        columns: [
            .text("owner_id"),
            .text("name"),
            .text("color"),
            .text("created_at"),
            .text("updated_at")
        ]
    ),
    Table(
        name: CATEGORIES_TABLE,
        columns: [
            .text("owner_id"),
            .text("name"),
            .text("color"),
            .text("created_at"),
            .text("updated_at")
        ]
    ),
    Table(
        name: TASK_EVENTS_TABLE,
        columns: [
            .text("owner_id"),
            .text("task_id"),
            .text("actor"),
            .text("event_type"),
            .text("title"),
            .text("body"),
            .text("metadata"),
            .text("created_at")
        ],
        indexes: [
            Index(name: "by_task_created", columns: [
                IndexedColumn.ascending("task_id"),
                IndexedColumn.ascending("created_at")
            ])
        ]
    ),
    Table(
        name: TASK_ATTACHMENTS_TABLE,
        columns: [
            .text("owner_id"),
            .text("task_id"),
            .text("filename"),
            .text("mime_type"),
            .integer("byte_size"),
            .text("preview_data_url"),
            .text("created_at")
        ],
        indexes: [
            Index(name: "by_task_created", columns: [
                IndexedColumn.ascending("task_id"),
                IndexedColumn.ascending("created_at")
            ])
        ]
    ),
    Table(
        name: AGENT_PROPOSALS_TABLE,
        columns: [
            .text("owner_id"),
            .text("task_id"),
            .text("proposal_type"),
            .text("status"),
            .text("title"),
            .text("body"),
            .text("payload"),
            .text("provenance"),
            .real("confidence"),
            .text("source"),
            .text("created_at"),
            .text("updated_at"),
            .text("decided_at"),
            .text("applied_at")
        ],
        indexes: [
            Index(name: "by_status", columns: [
                IndexedColumn.ascending("status"),
                IndexedColumn.ascending("created_at")
            ]),
            Index(name: "by_task_status", columns: [
                IndexedColumn.ascending("task_id"),
                IndexedColumn.ascending("status")
            ])
        ]
    )
)
