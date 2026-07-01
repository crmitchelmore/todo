import XCTest
@testable import CaptureCore

/// Captures the outgoing request so we can assert the /api/capture contract without a live backend.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequestBody: Data?
    nonisolated(unsafe) static var lastRequestURL: URL?
    nonisolated(unsafe) static var statusCode = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lastRequestURL = request.url
        // URLProtocol strips httpBody into httpBodyStream; read it back.
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let bufSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufSize)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            MockURLProtocol.lastRequestBody = data
        } else {
            MockURLProtocol.lastRequestBody = request.httpBody
        }
        let resp = HTTPURLResponse(
            url: request.url!,
            statusCode: MockURLProtocol.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"ok\":true}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class CaptureIngressTests: XCTestCase {
    private func mockedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testHTTPIngressPostsCaptureContract() async throws {
        MockURLProtocol.statusCode = 200
        let session = mockedSession()
        let ingress = HTTPCaptureIngress(backendURL: URL(string: "http://localhost:6060")!, session: session)

        let input = CaptureInput(rawText: "email Kate the report tomorrow 2pm", source: "share-extension")
        try await ingress.capture(input)

        XCTAssertEqual(MockURLProtocol.lastRequestURL?.path, "/api/capture")
        let body = try XCTUnwrap(MockURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["raw_text"] as? String, "email Kate the report tomorrow 2pm")
        XCTAssertEqual(json["source"] as? String, "share-extension")
        XCTAssertEqual(json["id"] as? String, input.id)
    }

    func testHTTPIngressThrowsOnServerError() async {
        MockURLProtocol.statusCode = 500
        let session = mockedSession()
        let ingress = HTTPCaptureIngress(backendURL: URL(string: "http://localhost:6060")!, session: session)
        do {
            try await ingress.capture(CaptureInput(rawText: "x", source: "app-intent"))
            XCTFail("expected failure on 500")
        } catch {
            // expected
        }
    }

    func testCaptureInputGeneratesLowercaseUUID() {
        let input = CaptureInput(rawText: "buy milk", source: "app-intent")
        XCTAssertEqual(input.id, input.id.lowercased())
        XCTAssertEqual(input.id.count, 36) // canonical UUID string length
    }

    func testHTTPIngressMarksURLOnlyCaptureForSummary() async throws {
        MockURLProtocol.statusCode = 200
        let session = mockedSession()
        let ingress = HTTPCaptureIngress(backendURL: URL(string: "http://localhost:6060")!, session: session)

        try await ingress.capture(CaptureInput(rawText: "https://example.com/article", source: "share-extension"))

        let body = try XCTUnwrap(MockURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["source"] as? String, URLSummaryCapture.source)
        XCTAssertEqual(json["raw_text"] as? String, "https://example.com/article")
    }

    func testURLSummaryCaptureOnlyMatchesBareHTTPURLs() {
        XCTAssertEqual(URLSummaryCapture.urlOnly(" https://example.com/article "), "https://example.com/article")
        XCTAssertNil(URLSummaryCapture.urlOnly("read https://example.com/article"))
        XCTAssertNil(URLSummaryCapture.urlOnly("obsidian://open?vault=Notes"))
        XCTAssertNil(URLSummaryCapture.urlOnly("example.com/article"))
    }
}
