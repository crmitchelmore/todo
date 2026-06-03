import Foundation

/// The credential the app holds after a successful Sign in with Apple exchange: an opaque,
/// server-revocable session token plus the user's internal id (== `owner_id` for local writes).
/// The Apple identity token itself is single-use and never stored.
public struct AuthSession: Sendable, Equatable {
    public let token: String
    public let userId: String
    public init(token: String, userId: String) {
        self.token = token
        self.userId = userId
    }
}

/// Anything that can hand out the current bearer token and react to the backend rejecting it.
/// The connector and ingress depend on this rather than on a concrete store, so out-of-process
/// surfaces can supply a Keychain-only reader.
public protocol TokenProviding: Sendable {
    func currentToken() -> String?
    /// Called when the backend returns 401 for a token we believed valid: the session was revoked
    /// or expired server-side, so drop it locally and surface a re-auth prompt.
    func invalidate()
}

private struct BackendAuthResponse: Decodable {
    let ok: Bool?
    let session_token: String?
    let user_id: String?
    let error: String?
}

/// Owns the Sign in with Apple flow and the resulting opaque session, persisting it in a shared
/// Keychain access group so the main app, Share Extension and App Intents all read the same login.
///
/// Deliberately small and UI-agnostic: the AppKit/UIKit layers run `ASAuthorizationController`,
/// then call `signIn(appleIdentityToken:rawNonce:)`. State changes are broadcast via `onChange`
/// so a view controller can swap between the sign-in gate and the capture UI.
public final class AuthStore: @unchecked Sendable, TokenProviding {
    private let backendURL: URL
    private let keychain: Keychain
    private let session: URLSession
    private let lock = NSLock()
    private var current: AuthSession?

    /// Fired (on the main queue) whenever the authentication state changes (sign in / out / 401).
    public var onChange: (@Sendable () -> Void)?

    public init(config: CaptureConfig, session: URLSession = .shared) {
        self.backendURL = config.backendURL
        self.session = session
        self.keychain = Keychain(
            service: "dev.crmitchelmore.capture.session",
            accessGroup: config.keychainAccessGroup
        )
        self.current = keychain.loadSession()
    }

    public var currentSession: AuthSession? {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    public var isAuthenticated: Bool { currentSession != nil }

    /// The owner id to stamp on locally-created rows so they match the server's owner-scoped
    /// writes and the per-user sync filter. Falls back to nil when signed out.
    public var ownerId: String? { currentSession?.userId }

    // MARK: TokenProviding

    public func currentToken() -> String? { currentSession?.token }

    public func invalidate() {
        clear()
    }

    // MARK: Flow

    /// Exchange an Apple identity token for an opaque session token. `rawNonce` is the un-hashed
    /// nonce we generated for this request; the backend checks `sha256(rawNonce)` against the
    /// token's `nonce` claim to bind the assertion to this login attempt.
    @discardableResult
    public func signIn(appleIdentityToken: String, rawNonce: String?, client: String) async throws -> AuthSession {
        var req = URLRequest(url: backendURL.appendingPathComponent("api/auth/apple"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        var body: [String: Any] = ["identity_token": appleIdentityToken, "client": client]
        if let rawNonce { body["nonce"] = rawNonce }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CaptureError.auth("no response")
        }
        let decoded = try? JSONDecoder().decode(BackendAuthResponse.self, from: data)
        guard http.statusCode == 200, decoded?.ok == true,
              let token = decoded?.session_token, let userId = decoded?.user_id else {
            throw CaptureError.auth(decoded?.error ?? "sign-in failed (\(http.statusCode))")
        }
        let session = AuthSession(token: token, userId: userId)
        store(session)
        return session
    }

    /// Best-effort server revoke, then drop the local session regardless of the network result.
    public func signOut() async {
        if let token = currentToken() {
            var req = URLRequest(url: backendURL.appendingPathComponent("api/auth/logout"))
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 8
            _ = try? await session.data(for: req)
        }
        clear()
    }

    // MARK: State

    private func store(_ session: AuthSession) {
        lock.lock()
        current = session
        lock.unlock()
        keychain.save(session)
        notify()
    }

    private func clear() {
        lock.lock()
        let had = current != nil
        current = nil
        lock.unlock()
        keychain.clear()
        if had { notify() }
    }

    private func notify() {
        guard let onChange else { return }
        DispatchQueue.main.async { onChange() }
    }
}

/// A no-op token provider for contexts with no signed-in user (the offline probe and unit tests).
/// Yields no bearer, so the backend will simply reject any networked call with 401 — which those
/// contexts never make.
public struct AnonymousToken: TokenProviding {
    public init() {}
    public func currentToken() -> String? { nil }
    public func invalidate() {}
}

/// Minimal Keychain wrapper for a single generic-password item shared across the app's processes
/// via an access group. Stores `userId\ntoken`. Keychain (not an App Group file) keeps the session
/// out of plaintext on disk and lets the OS scope it to the app's signing identity.
struct Keychain {
    let service: String
    let accessGroup: String?

    private func baseQuery() -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "session"
        ]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    func loadSession() -> AuthSession? {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let raw = String(data: data, encoding: .utf8) else { return nil }
        let parts = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let userId = String(parts[0]), token = String(parts[1])
        guard !userId.isEmpty, !token.isEmpty else { return nil }
        return AuthSession(token: token, userId: userId)
    }

    func save(_ session: AuthSession) {
        let value = "\(session.userId)\n\(session.token)"
        guard let data = value.data(using: .utf8) else { return }
        SecItemDelete(baseQuery() as CFDictionary)
        var q = baseQuery()
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
