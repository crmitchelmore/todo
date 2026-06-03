import Foundation

/// A single raw capture from an out-of-process surface (Share Extension, Siri/Shortcuts intent).
public struct CaptureInput: Codable, Sendable {
    /// Client-generated UUID — the backend uses it as an idempotency key so retries are safe.
    public var id: String
    public var rawText: String
    public var url: String?
    public var source: String
    public var createdAtClient: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        rawText: String,
        url: String? = nil,
        source: String,
        createdAtClient: Date = Date()
    ) {
        self.id = id
        self.rawText = rawText
        self.url = url
        self.source = source
        self.createdAtClient = createdAtClient
    }
}

/// How an out-of-process surface turns a raw capture into a `proposed` row. Extensions must NOT
/// open the app's PowerSync SQLite DB (separate process + concurrency risk), so they go through the
/// backend ingestion endpoint instead, falling back to a shared outbox when offline.
public protocol CaptureIngress: Sendable {
    func capture(_ input: CaptureInput) async throws
}

public enum CaptureIngressError: Error {
    case badStatus(Int)
    case noAppGroup
}

/// Posts a capture to the backend `/api/capture` endpoint. The backend forces `status='proposed'`
/// and the enrichment worker fills in suggestions, so the row syncs back to every client.
public struct HTTPCaptureIngress: CaptureIngress {
    private let backendURL: URL
    private let token: TokenProviding?
    private let session: URLSession

    public init(backendURL: URL, token: TokenProviding? = nil, session: URLSession = .shared) {
        self.backendURL = backendURL
        self.token = token
        self.session = session
    }

    public func capture(_ input: CaptureInput) async throws {
        var req = URLRequest(url: backendURL.appendingPathComponent("api/capture"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.applyBearer(token?.currentToken())
        req.timeoutInterval = 8
        let body: [String: Any] = [
            "id": input.id,
            "raw_text": input.rawText,
            "url": input.url as Any,
            "source": input.source
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw CaptureIngressError.badStatus(-1) }
        guard (200..<300).contains(http.statusCode) else {
            throw CaptureIngressError.badStatus(http.statusCode)
        }
    }
}

/// Durable offline queue in a shared App Group container. The Share Extension/intent writes a tiny
/// JSON record here when the network/backend is unavailable; the main app drains it on next launch.
public struct OutboxCaptureIngress: CaptureIngress {
    private let appGroupId: String

    public init(appGroupId: String) {
        self.appGroupId = appGroupId
    }

    private func outboxDir() throws -> URL {
        let fileManager = FileManager.default
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
        else { throw CaptureIngressError.noAppGroup }
        let dir = container.appendingPathComponent("capture-outbox", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func capture(_ input: CaptureInput) async throws {
        let dir = try outboxDir()
        let url = dir.appendingPathComponent("\(input.id).json")
        let data = try JSONEncoder.captureISO.encode(input)
        try data.write(to: url, options: .atomic)
    }

    /// Read and remove every pending capture (called by the main app to drain the queue).
    public func drain() throws -> [CaptureInput] {
        let fileManager = FileManager.default
        let dir = try outboxDir()
        let files = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        var out: [CaptureInput] = []
        for file in files {
            if let data = try? Data(contentsOf: file),
               let input = try? JSONDecoder.captureISO.decode(CaptureInput.self, from: data) {
                out.append(input)
            }
            try? fileManager.removeItem(at: file)
        }
        return out
    }
}

/// Tries the backend first; on any failure enqueues to the App Group outbox so a capture is never
/// lost. This is the ingress the Share Extension and App Intents use.
public struct ResilientCaptureIngress: CaptureIngress {
    private let http: HTTPCaptureIngress
    private let outbox: OutboxCaptureIngress?

    public init(backendURL: URL, appGroupId: String?, token: TokenProviding? = nil, session: URLSession = .shared) {
        self.http = HTTPCaptureIngress(backendURL: backendURL, token: token, session: session)
        self.outbox = appGroupId.map { OutboxCaptureIngress(appGroupId: $0) }
    }

    public func capture(_ input: CaptureInput) async throws {
        do {
            try await http.capture(input)
        } catch {
            if let outbox { try await outbox.capture(input) } else { throw error }
        }
    }
}

extension JSONEncoder {
    static var captureISO: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var captureISO: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
