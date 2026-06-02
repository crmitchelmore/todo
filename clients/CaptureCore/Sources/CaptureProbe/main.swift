import Foundation
import CaptureCore

// Headless end-to-end probe for the native data path: connect -> capture ->
// wait for on-device enrichment -> confirm -> wait for sync upload.
// Prints the row id so a caller can verify it landed in Postgres.
// Requires the local stack (docker compose) to be running.

let marker = "probe-\(Int(Date().timeIntervalSince1970))"
let store = TaskStore(config: .localDev)
do {
    try await store.connect()
    print("connected")

    let id = store.capture("\(marker) email client the report tomorrow 2pm")
    print("captured id=\(id)")

    try await Task.sleep(nanoseconds: 1_500_000_000)
    let suggested: String? = (try await store.db.getOptional(
        sql: "SELECT suggested_category FROM tasks WHERE id = ?",
        parameters: [id],
        mapper: { try $0.getStringOptional(name: "suggested_category") }
    )) ?? nil
    print("suggested_category=\(suggested ?? "nil")")

    try await store.confirm(id: id, title: nil, dueAt: nil, category: suggested)
    print("confirmed")

    try await Task.sleep(nanoseconds: 4_000_000_000)
    print("PROBE_ID=\(id)")
    print("PROBE_MARKER=\(marker)")
    exit(0)
} catch {
    print("PROBE_ERROR=\(error)")
    exit(1)
}
