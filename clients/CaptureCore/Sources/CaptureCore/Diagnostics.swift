import Foundation

public struct SyncTaskCounts: Sendable, Equatable, Decodable {
    public let total: Int
    public let proposed: Int
    public let active: Int
    public let done: Int
    public let cancelled: Int
    public let byStatus: [String: Int]
    public let lastUpdatedAt: Date?

    public init(total: Int, proposed: Int, active: Int, done: Int, cancelled: Int, byStatus: [String: Int], lastUpdatedAt: Date?) {
        self.total = total
        self.proposed = proposed
        self.active = active
        self.done = done
        self.cancelled = cancelled
        self.byStatus = byStatus
        self.lastUpdatedAt = lastUpdatedAt
    }

    enum CodingKeys: String, CodingKey {
        case total, proposed, active, done, cancelled
        case byStatus = "by_status"
        case lastUpdatedAt = "last_updated_at"
    }
}

public struct SyncDiagnosticsOwner: Sendable, Equatable, Decodable {
    public let id: String
    public let email: String?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, email
        case createdAt = "created_at"
    }
}

public struct SyncDiagnosticsEndpoints: Sendable, Equatable, Decodable {
    public let backendURL: String
    public let powersyncURL: String

    public init(backendURL: String, powersyncURL: String) {
        self.backendURL = backendURL
        self.powersyncURL = powersyncURL
    }

    enum CodingKeys: String, CodingKey {
        case backendURL = "backend_url"
        case powersyncURL = "powersync_url"
    }
}

public struct SyncDiagnosticsSession: Sendable, Equatable, Decodable {
    public let client: String?
    public let createdAt: Date?
    public let lastSeenAt: Date?
    public let expiresAt: Date?
    public let revokedAt: Date?

    enum CodingKeys: String, CodingKey {
        case client
        case createdAt = "created_at"
        case lastSeenAt = "last_seen_at"
        case expiresAt = "expires_at"
        case revokedAt = "revoked_at"
    }
}

public struct SyncDiagnosticsClientSessions: Sendable, Equatable, Decodable {
    public let client: String
    public let sessions: Int
    public let activeSessions: Int
    public let newestSeenAt: Date?

    enum CodingKeys: String, CodingKey {
        case client, sessions
        case activeSessions = "active_sessions"
        case newestSeenAt = "newest_seen_at"
    }
}

public struct ServerSyncDiagnostics: Sendable, Equatable, Decodable {
    public let ok: Bool
    public let owner: SyncDiagnosticsOwner
    public let endpoints: SyncDiagnosticsEndpoints
    public let serverCounts: SyncTaskCounts
    public let currentSession: SyncDiagnosticsSession?
    public let sessions: [SyncDiagnosticsClientSessions]

    enum CodingKeys: String, CodingKey {
        case ok, owner, endpoints, sessions
        case serverCounts = "server_counts"
        case currentSession = "current_session"
    }
}

public struct LocalSyncDiagnostics: Sendable, Equatable {
    public let ownerId: String?
    public let endpoints: SyncDiagnosticsEndpoints
    public let counts: SyncTaskCounts
    public let ownerIds: [String]

    public init(ownerId: String?, endpoints: SyncDiagnosticsEndpoints, counts: SyncTaskCounts, ownerIds: [String]) {
        self.ownerId = ownerId
        self.endpoints = endpoints
        self.counts = counts
        self.ownerIds = ownerIds
    }
}
