import Foundation
import OSLog
import CaptureCore
import Sentry

@MainActor
enum CaptureObservability {
    private static let logger = Logger(subsystem: "dev.crmitchelmore.capture.ios", category: "observability")
    private static var started = false
    private static var sentryStarted = false
    private static var diagnosticsSinkId: UUID?

    static func start() {
        guard !started else { return }
        started = true
        diagnosticsSinkId = CaptureDiagnostics.shared.addSink { event in
            Task { @MainActor in emit(event) }
        }
        if let dsn = configValue("SENTRY_DSN"), !dsn.contains("$(") {
            SentrySDK.start { options in
                options.dsn = dsn
                options.environment = configValue("SENTRY_ENVIRONMENT") ?? "development"
                options.tracesSampleRate = 0.1
                options.enableAutoSessionTracking = true
            }
            sentryStarted = true
        }
        wideEvent("native.observability.started", fields: ["surface": "ios"])
    }

    static func capture(_ error: Error, operation: String, fields: [String: String] = [:]) {
        wideEvent("native.error", fields: ["operation": operation, "error": error.localizedDescription].merging(fields) { first, _ in first })
        if sentryStarted { SentrySDK.capture(error: error) }
    }

    static func wideEvent(_ event: String, fields: [String: String] = [:]) {
        CaptureDiagnostics.record(
            severity: event == "native.error" ? .error : .info,
            category: "observability",
            name: event,
            message: event,
            fields: fields.merging(["service": "capture-ios"]) { first, _ in first }
        )
    }

    private static func emit(_ event: CaptureDiagnosticEvent) {
        var payload = event.fields
        payload["event"] = event.name
        payload["service"] = payload["service"] ?? "capture-ios"
        payload["timestamp"] = ISO8601DateFormatter().string(from: event.timestamp)
        payload["severity"] = event.severity.rawValue
        payload["category"] = event.category
        payload["message"] = event.message
        payload["action_id"] = event.actionId
        payload["action_name"] = event.actionName
        payload["sequence"] = "\(event.sequence)"
        if let durationMs = event.durationMs { payload["duration_ms"] = "\(durationMs)" }
        let data = (try? JSONSerialization.data(withJSONObject: payload.sortedMap, options: [.sortedKeys]))
        let encoded = data.flatMap { String(data: $0, encoding: .utf8) } ?? event.name
        logger.notice("\(encoded, privacy: .public)")
        guard sentryStarted else { return }
        let breadcrumb = Breadcrumb(level: event.sentryLevel, category: event.category)
        breadcrumb.message = event.message
        breadcrumb.type = event.name
        breadcrumb.data = payload
        SentrySDK.addBreadcrumb(breadcrumb)
    }

    private static func configValue(_ key: String) -> String? {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private extension CaptureDiagnosticEvent {
    var sentryLevel: SentryLevel {
        switch severity {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }
}

private extension Dictionary where Key == String, Value == String {
    var sortedMap: [String: String] {
        Dictionary(uniqueKeysWithValues: keys.sorted().map { ($0, self[$0] ?? "") })
    }
}
