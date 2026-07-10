import XCTest
import PowerSync
@testable import CaptureCore

/// Records `invalidate()` calls so we can assert a transient 401 never discards a valid session.
private final class SpyToken: TokenProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _invalidateCount = 0
    var invalidateCount: Int { lock.lock(); defer { lock.unlock() }; return _invalidateCount }
    func currentToken() -> String? { "valid-session-token" }
    func invalidate() { lock.lock(); _invalidateCount += 1; lock.unlock() }
}

/// Returns a configurable status code for the auth/token request.
private final class AuthMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var statusCode = 401
    nonisolated(unsafe) static var lastRequestURL: URL?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequestURL = request.url
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode,
                                   httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        let body = Self.statusCode == 200
            ? Data(#"{"token":"jwt","powersync_url":"http://localhost:8080"}"#.utf8)
            : Data(#"{"ok":false,"error":"unauthorized"}"#.utf8)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class BackendConnectorTests: XCTestCase {
    private func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [AuthMockURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    private func connector(_ token: TokenProviding, threshold: Int, grace: TimeInterval) -> BackendConnector {
        BackendConnector(
            config: .remote(backendHost: "example.test", powersyncHost: "ps.example.test"),
            token: token,
            session: session(),
            authFailureThreshold: threshold,
            authFailureGracePeriod: grace
        )
    }

    /// A single transient 401 must NOT discard the session — PowerSync should just retry.
    func testTransient401DoesNotInvalidateSession() async {
        AuthMockURLProtocol.statusCode = 401
        let token = SpyToken()
        let connector = connector(token, threshold: 3, grace: 90)
        for _ in 0..<2 {
            do { _ = try await connector.fetchCredentials(); XCTFail("expected 401") }
            catch { /* expected */ }
        }
        XCTAssertEqual(token.invalidateCount, 0, "a few quick 401s must not nuke a valid session")
    }

    /// Sustained 401s past the threshold (grace 0 = immediate) are a genuine logout.
    func testSustained401InvalidatesSession() async {
        AuthMockURLProtocol.statusCode = 401
        let token = SpyToken()
        let connector = connector(token, threshold: 2, grace: 0)
        for _ in 0..<2 {
            do { _ = try await connector.fetchCredentials() } catch { /* expected */ }
        }
        XCTAssertGreaterThanOrEqual(token.invalidateCount, 1, "a sustained run of 401s should sign out")
    }

    /// A success between failures resets the run so it can't accumulate toward a false logout.
    func testSuccessResetsFailureRun() async {
        let token = SpyToken()
        let connector = connector(token, threshold: 2, grace: 0)

        AuthMockURLProtocol.statusCode = 401
        do { _ = try await connector.fetchCredentials() } catch {}

        AuthMockURLProtocol.statusCode = 200
        _ = try? await connector.fetchCredentials() // resets the counter

        AuthMockURLProtocol.statusCode = 401
        do { _ = try await connector.fetchCredentials() } catch {}

        XCTAssertEqual(token.invalidateCount, 0, "an interleaved success must reset the 401 run")
    }

    func testSingleOriginWithPortPreservesBackendTokenPath() async {
        AuthMockURLProtocol.statusCode = 200
        AuthMockURLProtocol.lastRequestURL = nil
        let token = SpyToken()
        let connector = BackendConnector(
            config: .remote(
                backendHost: "capture-mini.example.test:10000",
                powersyncHost: "capture-mini.example.test:10000"
            ),
            token: token,
            session: session()
        )

        _ = try? await connector.fetchCredentials()

        XCTAssertEqual(
            AuthMockURLProtocol.lastRequestURL?.absoluteString,
            "https://capture-mini.example.test:10000/api/auth/token"
        )
    }

    func testFromEnvironmentIgnoresUnexpandedBuildSettings() {
        let config = CaptureConfig.fromEnvironment(
            backendHost: "$(CAPTURE_BACKEND_HOST)",
            powersyncHost: "$(CAPTURE_POWERSYNC_HOST)"
        )

        XCTAssertEqual(config.backendURL, CaptureConfig.production.backendURL)
        XCTAssertEqual(config.powersyncURL, CaptureConfig.production.powersyncURL)
    }
}
