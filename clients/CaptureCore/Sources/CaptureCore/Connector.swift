import Foundation
import PowerSync

public struct CaptureConfig: Sendable {
    /// Backend connector base URL (mints JWTs, applies the write path).
    public var backendURL: URL
    /// PowerSync service base URL the client streams from.
    public var powersyncURL: URL
    /// Single-user dev identity for M1.
    public var ownerId: String
    /// Shared App Group container id for the offline capture outbox (used by extensions/intents).
    public var appGroupId: String?
    /// Keychain access group that lets the main app, Share Extension and App Intents read the same
    /// session. Nil => the process's default access group (main app only).
    public var keychainAccessGroup: String?

    public init(
        backendURL: URL,
        powersyncURL: URL,
        ownerId: String = "00000000-0000-0000-0000-000000000001",
        appGroupId: String? = nil,
        keychainAccessGroup: String? = nil
    ) {
        self.backendURL = backendURL
        self.powersyncURL = powersyncURL
        self.ownerId = ownerId
        self.appGroupId = appGroupId
        self.keychainAccessGroup = keychainAccessGroup
    }

    /// Sensible default for a simulator/desktop talking to the local stack.
    public static let localDev = CaptureConfig(
        backendURL: URL(string: "http://localhost:6060")!,
        powersyncURL: URL(string: "http://localhost:8080")!,
        appGroupId: "group.dev.crmitchelmore.capture"
    )

    /// Remote deployment where the backend connector and PowerSync service are reachable over
    /// HTTPS. Both hosts may be the same when a single edge routes by path.
    ///
    ///   CaptureConfig.remote(
    ///     backendHost: "capture.example.com",
    ///     powersyncHost: "capture.example.com")
    public static func remote(
        backendHost: String,
        powersyncHost: String,
        ownerId: String = "00000000-0000-0000-0000-000000000001",
        appGroupId: String? = "group.dev.crmitchelmore.capture",
        keychainAccessGroup: String? = nil
    ) -> CaptureConfig {
        CaptureConfig(
            backendURL: URL(string: "https://\(backendHost)")!,
            powersyncURL: URL(string: "https://\(powersyncHost)")!,
            ownerId: ownerId,
            appGroupId: appGroupId,
            keychainAccessGroup: keychainAccessGroup
        )
    }

    /// The live Mac mini deployment, routed through one Tailscale HTTPS origin.
    public static let production = CaptureConfig.remote(
        backendHost: "bravos-mac-mini.taile313a5.ts.net:10000",
        powersyncHost: "bravos-mac-mini.taile313a5.ts.net:10000"
    )

    /// Reads `CAPTURE_BACKEND_HOST` / `CAPTURE_POWERSYNC_HOST` from the environment (or the
    /// matching Info.plist keys), falling back to the live Mac mini `production` deployment when
    /// unset. Set both to a localhost pair (and run docker-compose) to target the local stack in
    /// dev without code changes.
    public static func fromEnvironment(
        backendHost: String? = ProcessInfo.processInfo.environment["CAPTURE_BACKEND_HOST"],
        powersyncHost: String? = ProcessInfo.processInfo.environment["CAPTURE_POWERSYNC_HOST"],
        keychainAccessGroup: String? = ProcessInfo.processInfo.environment["CAPTURE_KEYCHAIN_ACCESS_GROUP"]
    ) -> CaptureConfig {
        let infoBackendHost = infoString("CAPTURE_BACKEND_HOST")
        let infoPowerSyncHost = infoString("CAPTURE_POWERSYNC_HOST")
        let accessGroup = resolvedKeychainAccessGroup(keychainAccessGroup ?? infoString("CAPTURE_KEYCHAIN_ACCESS_GROUP"))

        guard let backendHost = nonEmpty(backendHost) ?? nonEmpty(infoBackendHost),
              let powersyncHost = nonEmpty(powersyncHost) ?? nonEmpty(infoPowerSyncHost) else {
            var config = CaptureConfig.production
            config.keychainAccessGroup = accessGroup
            return config
        }
        return .remote(
            backendHost: backendHost,
            powersyncHost: powersyncHost,
            keychainAccessGroup: accessGroup
        )
    }

    private static func infoString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        guard !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private static func resolvedKeychainAccessGroup(_ raw: String?) -> String? {
        guard let group = nonEmpty(raw) else { return nil }
        if group.contains("$(") {
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
            guard bundleIdentifier.hasPrefix("dev.crmitchelmore.capture.ios") else { return nil }
            return "8X4ZN58TYH.dev.crmitchelmore.capture.session"
        }
        return group
    }

    /// Ingress for out-of-process surfaces (Share Extension, App Intents): backend POST with an
    /// App Group outbox fallback. Never opens PowerSync. Authenticates with the shared session.
    public func makeIngress(token: TokenProviding, session: URLSession = .shared) -> ResilientCaptureIngress {
        ResilientCaptureIngress(backendURL: backendURL, appGroupId: appGroupId, token: token, session: session)
    }

    /// The App Group outbox, when configured. Used by the main app to drain captures that an
    /// extension/intent enqueued while the backend was unreachable.
    public func makeOutbox() -> OutboxCaptureIngress? {
        appGroupId.map { OutboxCaptureIngress(appGroupId: $0) }
    }

    /// Drains any captures queued by extensions/intents (offline) and re-posts them to the backend.
    /// Safe to call on every app launch/foreground: idempotent (each capture carries a stable id),
    /// and anything that still fails is re-enqueued so a capture is never lost. Returns the number
    /// of captures successfully flushed.
    @discardableResult
    public func drainOutbox(token: TokenProviding, session: URLSession = .shared) async -> Int {
        guard let outbox = makeOutbox() else { return 0 }
        let pending = (try? outbox.drain()) ?? []
        guard !pending.isEmpty else { return 0 }
        let http = HTTPCaptureIngress(backendURL: backendURL, token: token, session: session)
        var flushed = 0
        for input in pending {
            do {
                try await http.capture(input)
                flushed += 1
            } catch {
                try? await outbox.capture(input) // still offline — keep it for next time
            }
        }
        return flushed
    }
}

private struct TokenResponse: Decodable {
    let token: String
    let powersync_url: String?
}

/// Connects the local-first SQLite DB to our self-hosted PowerSync + backend.
/// Mirrors the web `BackendConnector`: short-lived JWT for credentials, and a
/// background drain of the local write queue to Postgres via the backend.
public final class BackendConnector: PowerSyncBackendConnectorProtocol, @unchecked Sendable {
    private let config: CaptureConfig
    private let session: URLSession
    private let token: TokenProviding

    // A single transient 401 (e.g. a backend redeploy, a brief DB blip, a proxy hiccup) must NOT
    // discard a still-valid 30-day session — doing so left the StreamingSyncClient permanently
    // stuck with queued, never-uploaded ops. We only treat the session as genuinely
    // revoked/expired after a *sustained* run of 401s; transient ones are thrown so PowerSync
    // retries with backoff and re-establishes sync on its own once the backend is healthy again.
    private let authFailureLock = NSLock()
    private var firstAuthFailureAt: Date?
    private var consecutiveAuthFailures = 0
    private let authFailureThreshold: Int
    private let authFailureGracePeriod: TimeInterval

    public init(
        config: CaptureConfig,
        token: TokenProviding,
        session: URLSession = .shared,
        authFailureThreshold: Int = 3,
        authFailureGracePeriod: TimeInterval = 90
    ) {
        self.config = config
        self.token = token
        self.session = session
        self.authFailureThreshold = authFailureThreshold
        self.authFailureGracePeriod = authFailureGracePeriod
    }

    /// Record a 401 from an authenticated request. Returns `true` only once failures have been
    /// sustained (>= threshold consecutive 401s spanning >= the grace period), i.e. this really is
    /// a revoked/expired session rather than a transient backend blip.
    private func shouldInvalidateAfterUnauthorized() -> Bool {
        authFailureLock.lock(); defer { authFailureLock.unlock() }
        let now = Date()
        if firstAuthFailureAt == nil { firstAuthFailureAt = now }
        consecutiveAuthFailures += 1
        let elapsed = now.timeIntervalSince(firstAuthFailureAt ?? now)
        return consecutiveAuthFailures >= authFailureThreshold && elapsed >= authFailureGracePeriod
    }

    /// Any successful authenticated round-trip clears the transient-failure run.
    private func recordAuthSuccess() {
        authFailureLock.lock(); defer { authFailureLock.unlock() }
        firstAuthFailureAt = nil
        consecutiveAuthFailures = 0
    }

    public func fetchCredentials() async throws -> PowerSyncCredentials? {
        let url = config.backendURL.appendingPathComponent("api/auth/token")
        var request = URLRequest(url: url)
        request.applyBearer(token.currentToken())
        let (data, http) = try await performDataRequest(request, operation: "sync.fetch_credentials")
        if http.statusCode == 401 {
            // Only sign the user out after sustained 401s; otherwise keep the session and let
            // PowerSync retry — a transient blip must not nuke a valid login.
            if shouldInvalidateAfterUnauthorized() { token.invalidate() }
            throw CaptureError.auth("session expired")
        }
        guard http.statusCode == 200 else {
            throw CaptureError.auth("token request failed (\(http.statusCode))")
        }
        recordAuthSuccess()
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return PowerSyncCredentials(
            endpoint: config.powersyncURL.absoluteString,
            token: decoded.token
        )
    }

    public func uploadData(database: PowerSyncDatabaseProtocol) async throws {
        guard let transaction = try await database.getNextCrudTransaction() else { return }

        var ops: [[String: Any]] = []
        for entry in transaction.crud {
            var op: [String: Any] = [
                "op": entry.op.rawValue,
                "type": entry.table,
                "id": entry.id
            ]
            if let data = entry.opData {
                var typed: [String: Any] = [:]
                for (k, v) in data { typed[k] = v ?? NSNull() }
                op["data"] = typed
            }
            ops.append(op)
        }
        CaptureDiagnostics.record(
            severity: .info,
            category: "sync",
            name: "sync.upload.queue",
            message: "Uploading local CRUD transaction",
            fields: ["crud_count": "\(ops.count)"]
        )

        var request = URLRequest(url: config.backendURL.appendingPathComponent("api/data"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.applyBearer(token.currentToken())
        request.httpBody = try JSONSerialization.data(withJSONObject: ["ops": ops])

        let (body, http) = try await performDataRequest(request, operation: "sync.upload_data")
        if http.statusCode == 401 {
            if shouldInvalidateAfterUnauthorized() { token.invalidate() }
            throw CaptureError.auth("session expired")
        }
        guard http.statusCode == 200 else {
            let text = String(data: body, encoding: .utf8) ?? ""
            throw CaptureError.upload("upload failed: \(text)")
        }

        recordAuthSuccess()
        try await transaction.complete()
    }

    private func performDataRequest(_ request: URLRequest, operation: String) async throws -> (Data, HTTPURLResponse) {
        let startedAt = CaptureDiagnostics.recordHTTPRequestStart(
            request,
            operation: operation,
            requestBytes: request.httpBody?.count
        )
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            CaptureDiagnostics.recordHTTPResponse(nil, data: nil, operation: operation, startedAt: startedAt, error: error)
            throw error
        }
        CaptureDiagnostics.recordHTTPResponse(response, data: data, operation: operation, startedAt: startedAt)
        guard let http = response as? HTTPURLResponse else { throw CaptureError.upload("\(operation) failed: no response") }
        return (data, http)
    }
}

public enum CaptureError: Error, Sendable {
    case auth(String)
    case upload(String)

    /// The human-readable detail carried by the error (used to surface backend messages in the UI).
    public var message: String {
        switch self {
        case .auth(let m), .upload(let m): return m
        }
    }
}

extension URLRequest {
    /// Adds the opaque session token when one is present (no-op when signed out).
    mutating func applyBearer(_ token: String?) {
        if let token, !token.isEmpty {
            setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}
