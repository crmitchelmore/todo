import Foundation
import OSLog
import Sentry

@MainActor
enum CaptureObservability {
    private static let logger = Logger(subsystem: "dev.crmitchelmore.capture.ios", category: "observability")
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        guard let dsn = configValue("SENTRY_DSN"), !dsn.contains("$(") else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = configValue("SENTRY_ENVIRONMENT") ?? "development"
            options.tracesSampleRate = 0.1
            options.enableAutoSessionTracking = true
        }
        wideEvent("native.observability.started", fields: ["surface": "ios"])
    }

    static func capture(_ error: Error, operation: String, fields: [String: String] = [:]) {
        wideEvent("native.error", fields: ["operation": operation, "error": error.localizedDescription].merging(fields) { first, _ in first })
        SentrySDK.capture(error: error)
    }

    static func wideEvent(_ event: String, fields: [String: String] = [:]) {
        var payload = fields
        payload["event"] = event
        payload["service"] = "capture-ios"
        payload["timestamp"] = ISO8601DateFormatter().string(from: Date())
        let data = (try? JSONSerialization.data(withJSONObject: payload.sortedMap, options: [.sortedKeys]))
        let encoded = data.flatMap { String(data: $0, encoding: .utf8) } ?? event
        logger.notice("\(encoded, privacy: .public)")
    }

    private static func configValue(_ key: String) -> String? {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private extension Dictionary where Key == String, Value == String {
    var sortedMap: [String: String] {
        Dictionary(uniqueKeysWithValues: keys.sorted().map { ($0, self[$0] ?? "") })
    }
}
