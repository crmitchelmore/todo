import Combine
import Foundation

public enum CaptureDiagnosticSeverity: String, Codable, CaseIterable, Sendable {
    case debug
    case info
    case warning
    case error
}

public struct CaptureDiagnosticActionContext: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
}

public struct CaptureDiagnosticEvent: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let sequence: Int
    public let timestamp: Date
    public let severity: CaptureDiagnosticSeverity
    public let category: String
    public let name: String
    public let message: String
    public let actionId: String
    public let actionName: String
    public let durationMs: Int?
    public let fields: [String: String]
}

public struct CaptureDiagnosticActionGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let startedAt: Date
    public let updatedAt: Date
    public let severity: CaptureDiagnosticSeverity
    public let events: [CaptureDiagnosticEvent]
}

public final class CaptureDiagnostics: ObservableObject, @unchecked Sendable {
    public static let shared = CaptureDiagnostics()
    public typealias Sink = @Sendable (CaptureDiagnosticEvent) -> Void

    @TaskLocal public static var currentAction: CaptureDiagnosticActionContext?

    @Published public private(set) var events: [CaptureDiagnosticEvent] = []

    private let maxEvents = 1_500
    private var nextSequence = 1
    private let sinkLock = NSLock()
    private var sinks: [UUID: Sink] = [:]
    private let exportEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private init() {}

    @discardableResult
    public static func recordHTTPRequestStart(
        _ request: URLRequest,
        operation: String,
        requestBytes: Int? = nil
    ) -> Date {
        var fields = request.diagnosticFields
        fields["operation"] = operation
        if let requestBytes { fields["request_bytes"] = "\(requestBytes)" }
        record(
            severity: .info,
            category: "network",
            name: "network.request.outbound",
            message: "\(request.httpMethod ?? "GET") \(request.url?.path.nilIfEmptyForDiagnostics ?? "/")",
            fields: fields
        )
        return Date()
    }

    public static func recordHTTPResponse(
        _ response: URLResponse?,
        data: Data?,
        operation: String,
        startedAt: Date,
        error: Error? = nil
    ) {
        var fields: [String: String] = [
            "operation": operation,
            "duration_ms": "\(durationMs(since: startedAt))"
        ]
        if let http = response as? HTTPURLResponse {
            fields["http_status"] = "\(http.statusCode)"
            fields["status_class"] = "\(http.statusCode / 100)xx"
            fields["url_host"] = http.url?.host ?? "unknown"
            fields["url_path"] = http.url?.path.nilIfEmptyForDiagnostics ?? "/"
        } else if let response {
            fields["response_type"] = String(describing: type(of: response))
        } else {
            fields["response_type"] = "none"
        }
        if let data { fields["response_bytes"] = "\(data.count)" }
        if let error {
            fields.merge(error.diagnosticFields) { first, _ in first }
        }
        record(
            severity: error == nil ? .info : .error,
            category: "network",
            name: error == nil ? "network.response.inbound" : "network.request.failed",
            message: error.map { redacted($0.localizedDescription) } ?? "Response received",
            durationMs: durationMs(since: startedAt),
            fields: fields
        )
    }

    public static func record(
        severity: CaptureDiagnosticSeverity = .info,
        category: String,
        name: String,
        message: String,
        durationMs: Int? = nil,
        fields: [String: String] = [:],
        actionId: String? = nil,
        actionName: String? = nil
    ) {
        let context = currentAction
        shared.append(
            severity: severity,
            category: category,
            name: name,
            message: redacted(message),
            durationMs: durationMs,
            fields: fields.mapValues(redacted),
            actionId: actionId ?? context?.id ?? "ungrouped",
            actionName: actionName ?? context?.name ?? "Ungrouped"
        )
    }

    @discardableResult
    public static func actionStarted(
        _ name: String,
        fields: [String: String] = [:]
    ) -> CaptureDiagnosticActionContext {
        let context = CaptureDiagnosticActionContext(id: UUID().uuidString.lowercased(), name: name)
        record(
            severity: .info,
            category: "action",
            name: "action.started",
            message: name,
            fields: fields,
            actionId: context.id,
            actionName: context.name
        )
        return context
    }

    public static func actionCompleted(
        _ context: CaptureDiagnosticActionContext,
        startedAt: Date,
        fields: [String: String] = [:]
    ) {
        record(
            severity: .info,
            category: "action",
            name: "action.completed",
            message: context.name,
            durationMs: durationMs(since: startedAt),
            fields: fields,
            actionId: context.id,
            actionName: context.name
        )
    }

    public static func actionFailed(
        _ context: CaptureDiagnosticActionContext,
        startedAt: Date,
        error: Error,
        fields: [String: String] = [:]
    ) {
        record(
            severity: .error,
            category: "action",
            name: "action.failed",
            message: error.localizedDescription,
            durationMs: durationMs(since: startedAt),
            fields: fields.merging(error.diagnosticFields) { first, _ in first },
            actionId: context.id,
            actionName: context.name
        )
    }

    public static func withAction<T>(
        _ name: String,
        fields: [String: String] = [:],
        operation: () async throws -> T
    ) async throws -> T {
        let context = actionStarted(name, fields: fields)
        let startedAt = Date()
        do {
            let result = try await operation()
            actionCompleted(context, startedAt: startedAt)
            return result
        } catch {
            actionFailed(context, startedAt: startedAt, error: error)
            throw error
        }
    }

    public func clear() {
        DispatchQueue.main.async {
            self.events.removeAll()
            self.nextSequence = 1
        }
    }

    @discardableResult
    public func addSink(_ sink: @escaping Sink) -> UUID {
        let id = UUID()
        sinkLock.lock()
        sinks[id] = sink
        sinkLock.unlock()
        return id
    }

    public func removeSink(_ id: UUID) {
        sinkLock.lock()
        sinks.removeValue(forKey: id)
        sinkLock.unlock()
    }

    public var actionGroups: [CaptureDiagnosticActionGroup] {
        let grouped = Dictionary(grouping: events, by: \.actionId)
        return grouped.values.map { items in
            let sorted = items.sorted { $0.timestamp < $1.timestamp }
            let worst = sorted.map(\.severity).max(by: Self.severitySort) ?? .info
            return CaptureDiagnosticActionGroup(
                id: sorted.first?.actionId ?? "ungrouped",
                name: sorted.first?.actionName ?? "Ungrouped",
                startedAt: sorted.first?.timestamp ?? Date(),
                updatedAt: sorted.last?.timestamp ?? Date(),
                severity: worst,
                events: sorted
            )
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func exportJSON() -> String {
        guard let data = try? exportEncoder.encode(events),
              let raw = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return raw
    }

    private func append(
        severity: CaptureDiagnosticSeverity,
        category: String,
        name: String,
        message: String,
        durationMs: Int?,
        fields: [String: String],
        actionId: String,
        actionName: String
    ) {
        DispatchQueue.main.async {
            let event = CaptureDiagnosticEvent(
                id: UUID().uuidString.lowercased(),
                sequence: self.nextSequence,
                timestamp: Date(),
                severity: severity,
                category: category,
                name: name,
                message: message,
                actionId: actionId,
                actionName: actionName,
                durationMs: durationMs,
                fields: fields
            )
            self.nextSequence += 1
            self.events.append(event)
            if self.events.count > self.maxEvents {
                self.events.removeFirst(self.events.count - self.maxEvents)
            }
            let sinks = self.snapshotSinks()
            for sink in sinks { sink(event) }
        }
    }

    private func snapshotSinks() -> [Sink] {
        sinkLock.lock()
        let values = Array(sinks.values)
        sinkLock.unlock()
        return values
    }

    private static func severitySort(_ lhs: CaptureDiagnosticSeverity, _ rhs: CaptureDiagnosticSeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    private static func durationMs(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
    }

    fileprivate static func redacted(_ value: String) -> String {
        let patterns = [
            #"Bearer\s+[A-Za-z0-9._~+/=-]+"#,
            #""password"\s*:\s*"[^"]*""#,
            #""session_token"\s*:\s*"[^"]*""#,
            #""token"\s*:\s*"[^"]*""#
        ]
        return patterns.reduce(String(value.prefix(2_000))) { current, pattern in
            current.replacingOccurrences(of: pattern, with: "[redacted]", options: .regularExpression)
        }
    }
}

private extension CaptureDiagnosticSeverity {
    var rank: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }
}

private extension URLRequest {
    var diagnosticFields: [String: String] {
        [
            "http_method": httpMethod ?? "GET",
            "url_scheme": url?.scheme ?? "unknown",
            "url_host": url?.host ?? "unknown",
            "url_path": url?.path.nilIfEmptyForDiagnostics ?? "/",
            "has_authorization": value(forHTTPHeaderField: "Authorization") == nil ? "false" : "true",
            "content_type": value(forHTTPHeaderField: "Content-Type") ?? "none",
            "timeout_s": "\(Int(timeoutInterval))"
        ]
    }
}

private extension Error {
    var diagnosticFields: [String: String] {
        [
            "error_type": String(describing: type(of: self)),
            "error_message": CaptureDiagnostics.redacted(localizedDescription)
        ]
    }
}

private extension String {
    var nilIfEmptyForDiagnostics: String? {
        isEmpty ? nil : self
    }
}
