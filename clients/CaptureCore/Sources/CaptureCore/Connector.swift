import Foundation
import PowerSync

public struct CaptureConfig: Sendable {
    /// Backend connector base URL (mints JWTs, applies the write path).
    public var backendURL: URL
    /// PowerSync service base URL the client streams from.
    public var powersyncURL: URL
    /// Single-user dev identity for M1.
    public var ownerId: String

    public init(backendURL: URL, powersyncURL: URL, ownerId: String = "00000000-0000-0000-0000-000000000001") {
        self.backendURL = backendURL
        self.powersyncURL = powersyncURL
        self.ownerId = ownerId
    }

    /// Sensible default for a simulator/desktop talking to the local stack.
    public static let localDev = CaptureConfig(
        backendURL: URL(string: "http://localhost:6060")!,
        powersyncURL: URL(string: "http://localhost:8080")!
    )
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

    public init(config: CaptureConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func fetchCredentials() async throws -> PowerSyncCredentials? {
        let url = config.backendURL.appendingPathComponent("api/auth/token")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CaptureError.auth("token request failed")
        }
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

        var request = URLRequest(url: config.backendURL.appendingPathComponent("api/data"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["ops": ops])

        let (body, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let text = String(data: body, encoding: .utf8) ?? ""
            throw CaptureError.upload("upload failed: \(text)")
        }

        try await transaction.complete()
    }
}

public enum CaptureError: Error, Sendable {
    case auth(String)
    case upload(String)
}
