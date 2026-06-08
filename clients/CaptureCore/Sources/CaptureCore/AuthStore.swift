import Foundation

/// The credential the app holds after a successful sign-in: an opaque, server-revocable session
/// token plus the user's internal id (== `owner_id` for local writes). The password is never stored.
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
    let mfa_required: Bool?
    let mfa_challenge: String?
    let error: String?
}

/// Owns the email + password sign-in flow and the resulting opaque session, persisting it in a
/// shared Keychain access group so the main app, Share Extension and App Intents all read the
/// same login.
///
/// Deliberately small and UI-agnostic: the AppKit/UIKit layers collect an email + password, then
/// call `signIn(email:password:client:)` or `register(email:password:client:)`. State changes are
/// broadcast via `onChange` so a view controller can swap between the sign-in gate and capture UI.
public final class AuthStore: @unchecked Sendable, TokenProviding {
    private static let sessionService = "dev.crmitchelmore.capture.session"

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
        let configuredKeychain = Keychain(
            service: Self.sessionService,
            accessGroup: config.keychainAccessGroup
        )
        self.keychain = configuredKeychain
        if let session = configuredKeychain.loadSession() {
            self.current = session
        } else if config.keychainAccessGroup != nil {
            let legacyKeychain = Keychain(service: Self.sessionService, accessGroup: nil)
            let legacySession = legacyKeychain.loadSession()
            self.current = legacySession
            if let legacySession {
                configuredKeychain.save(legacySession)
                legacyKeychain.clear()
            }
        } else {
            self.current = nil
        }
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

    /// Sign in with an existing email + password, exchanging them for an opaque session token.
    @discardableResult
    public func signIn(email: String, password: String, client: String) async throws -> AuthSession {
        try await authenticate(path: "api/auth/login", email: email, password: password, client: client)
    }

    /// Create a new account with an email + password, returning the opaque session for it.
    @discardableResult
    public func register(email: String, password: String, client: String) async throws -> AuthSession {
        try await authenticate(path: "api/auth/register", email: email, password: password, client: client)
    }

    /// Passwordless sign-in, step 1: ask the backend to email a one-time code. Always succeeds
    /// server-side (no account enumeration); throws only on a network/transport failure.
    public func requestEmailCode(email: String) async throws {
        try await postIssue(path: "api/auth/email-code", body: ["email": email])
    }

    /// Passwordless sign-in, step 2: exchange the emailed code for a session.
    @discardableResult
    public func verifyEmailCode(email: String, code: String, client: String) async throws -> AuthSession {
        try await postSession(path: "api/auth/email-code/verify", body: ["email": email, "code": code, "client": client])
    }

    /// Forgot password, step 1: ask the backend to email a reset code (always succeeds — no enumeration).
    public func requestPasswordReset(email: String) async throws {
        try await postIssue(path: "api/auth/forgot", body: ["email": email])
    }

    /// Forgot password, step 2: set a new password with the emailed code; signs in on success.
    @discardableResult
    public func resetPassword(email: String, code: String, password: String, client: String) async throws -> AuthSession {
        try await postSession(path: "api/auth/reset", body: ["email": email, "code": code, "password": password, "client": client])
    }

    /// Native passkey registration, step 1: fetch WebAuthn creation options for the signed-in user.
    public func beginPasskeyRegistration() async throws -> PasskeyRegistrationOptions {
        guard let token = currentToken() else { throw CaptureError.auth("not signed in") }
        return try await postJSON(
            path: "api/auth/passkeys/register/options",
            body: [:],
            bearer: token,
            decode: PasskeyRegistrationOptions.self
        )
    }

    /// Native passkey registration, step 2: verify the platform credential with the backend.
    public func finishPasskeyRegistration(_ result: PasskeyRegistrationResult) async throws {
        guard let token = currentToken() else { throw CaptureError.auth("not signed in") }
        _ = try await postJSON(
            path: "api/auth/passkeys/register/verify",
            body: result.requestBody(),
            bearer: token,
            decode: BackendAuthResponse.self
        )
    }

    /// Native passkey sign-in, step 1: fetch WebAuthn assertion options. Email is optional so
    /// account-discoverable passkeys can still work when the backend/browser combination supports it.
    public func beginPasskeySignIn(email: String? = nil) async throws -> PasskeyAuthenticationOptions {
        let body: [String: Any] = ["email": email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""]
        return try await postJSON(
            path: "api/auth/passkeys/login/options",
            body: body,
            bearer: nil,
            decode: PasskeyAuthenticationOptions.self
        )
    }

    /// Native passkey sign-in, step 2: verify the assertion and store the returned session.
    @discardableResult
    public func finishPasskeySignIn(_ result: PasskeyAuthenticationResult, client: String) async throws -> AuthSession {
        try await postSession(
            path: "api/auth/passkeys/login/verify",
            body: result.requestBody(client: client)
        )
    }

    public func fetchSyncDiagnostics() async throws -> ServerSyncDiagnostics {
        guard let token = currentToken() else { throw CaptureError.auth("not signed in") }
        var req = URLRequest(url: backendURL.appendingPathComponent("api/diagnostics/sync"))
        req.httpMethod = "GET"
        req.applyBearer(token)
        req.timeoutInterval = 15
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw CaptureError.auth("no response") }
        guard http.statusCode == 200 else {
            let decoded = try? JSONDecoder().decode(BackendAuthResponse.self, from: data)
            throw CaptureError.auth(decoded?.error ?? "diagnostics failed (\(http.statusCode))")
        }
        return try Self.diagnosticsDecoder.decode(ServerSyncDiagnostics.self, from: data)
    }

    /// POST a body to an always-200 issuance endpoint; throws only on transport/5xx failure.
    private func postIssue(path: String, body: [String: Any]) async throws {
        var req = URLRequest(url: backendURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw CaptureError.auth("no response") }
        guard http.statusCode == 200 else {
            let decoded = try? JSONDecoder().decode(BackendAuthResponse.self, from: data)
            throw CaptureError.auth(decoded?.error ?? "request failed (\(http.statusCode))")
        }
    }

    private func postJSON<T: Decodable>(
        path: String,
        body: [String: Any],
        bearer: String?,
        decode type: T.Type
    ) async throws -> T {
        var req = URLRequest(url: backendURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.applyBearer(bearer)
        req.timeoutInterval = 20
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw CaptureError.auth("no response") }
        let decodedError = try? JSONDecoder().decode(BackendAuthResponse.self, from: data)
        guard http.statusCode == 200, decodedError?.ok != false else {
            throw CaptureError.auth(decodedError?.error ?? "request failed (\(http.statusCode))")
        }
        return try JSONDecoder().decode(type, from: data)
    }

    /// POST a body to an endpoint that returns a session, storing it and signing the user in.
    @discardableResult
    private func postSession(path: String, body: [String: Any]) async throws -> AuthSession {
        var req = URLRequest(url: backendURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw CaptureError.auth("no response") }
        let decoded = try? JSONDecoder().decode(BackendAuthResponse.self, from: data)
        if http.statusCode == 200, decoded?.ok == true, decoded?.mfa_required == true {
            throw CaptureError.auth("This account requires a second factor. Use email/password on web to complete MFA.")
        }
        guard http.statusCode == 200, decoded?.ok == true,
              let token = decoded?.session_token, let userId = decoded?.user_id else {
            throw CaptureError.auth(decoded?.error ?? "sign-in failed (\(http.statusCode))")
        }
        let session = AuthSession(token: token, userId: userId)
        store(session)
        return session
    }

    private func authenticate(path: String, email: String, password: String, client: String) async throws -> AuthSession {
        var req = URLRequest(url: backendURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        let body: [String: Any] = ["email": email, "password": password, "client": client]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw CaptureError.auth("no response")
        }
        let decoded = try? JSONDecoder().decode(BackendAuthResponse.self, from: data)
        if http.statusCode == 200, decoded?.ok == true, decoded?.mfa_required == true {
            throw CaptureError.auth("This account requires a second factor. Use email/password on web to complete MFA.")
        }
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

    private static let diagnosticsDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = ISO8601.date(raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date")
            }
            return date
        }
        return decoder
    }()
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
