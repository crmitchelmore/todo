import Foundation
import PowerSync

public let TASKS_TABLE = "tasks"
public let TAGS_TABLE = "tags"

/// Client-side SQLite schema. Mirrors Postgres `public.tasks` / `public.tags`. The `id`
/// column is auto-created by PowerSync — never declare it.
public let AppSchema = Schema(
    Table(
        name: TASKS_TABLE,
        columns: [
            .text("owner_id"),
            .text("title"),
            .text("notes"),
            .text("status"),
            .text("category"),
            .text("tags"),               // JSON array of tag names ("projects" are tags too)
            .text("due_at"),
            .integer("priority"),
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
            Index(name: "by_status", columns: [IndexedColumn.ascending("status")])
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
    )
)
