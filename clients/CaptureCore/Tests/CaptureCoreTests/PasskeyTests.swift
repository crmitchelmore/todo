import XCTest
@testable import CaptureCore

final class PasskeyTests: XCTestCase {
    func testRegistrationOptionsDecodeSimpleWebAuthnShape() throws {
        let json = Data("""
        {
          "ok": true,
          "options": {
            "challenge": "AQIDBA",
            "rp": { "name": "Capture", "id": "example.com" },
            "user": { "id": "BQYHCA", "name": "me@example.com", "displayName": "me@example.com" },
            "pubKeyCredParams": []
          }
        }
        """.utf8)

        let options = try JSONDecoder().decode(PasskeyRegistrationOptions.self, from: json)
        XCTAssertEqual(options.challenge, Data([1, 2, 3, 4]))
        XCTAssertEqual(options.relyingPartyId, "example.com")
        XCTAssertEqual(options.userName, "me@example.com")
        XCTAssertEqual(options.userId, Data([5, 6, 7, 8]))
    }

    func testAuthenticationOptionsDecodeSimpleWebAuthnShape() throws {
        let json = Data("""
        {
          "ok": true,
          "options": {
            "challenge": "AQIDBA",
            "rpId": "example.com",
            "userVerification": "required"
          }
        }
        """.utf8)

        let options = try JSONDecoder().decode(PasskeyAuthenticationOptions.self, from: json)
        XCTAssertEqual(options.challenge, Data([1, 2, 3, 4]))
        XCTAssertEqual(options.relyingPartyId, "example.com")
    }

    func testNativePasskeyRegistrationResultEncodesSimpleWebAuthnResponse() throws {
        let result = PasskeyRegistrationResult(
            credentialId: Data([1, 2, 3]),
            clientDataJSON: Data([4, 5, 6]),
            attestationObject: Data([7, 8, 9])
        )

        let body = result.requestBody()
        let response = try XCTUnwrap(body["response"] as? [String: Any])
        XCTAssertEqual(response["id"] as? String, "AQID")
        XCTAssertEqual(response["rawId"] as? String, "AQID")
        XCTAssertEqual(response["type"] as? String, "public-key")
        let nested = try XCTUnwrap(response["response"] as? [String: Any])
        XCTAssertEqual(nested["clientDataJSON"] as? String, "BAUG")
        XCTAssertEqual(nested["attestationObject"] as? String, "BwgJ")
    }

    func testNativePasskeyAuthenticationResultEncodesSimpleWebAuthnResponse() throws {
        let result = PasskeyAuthenticationResult(
            credentialId: Data([1, 2, 3]),
            clientDataJSON: Data([4, 5, 6]),
            authenticatorData: Data([7, 8, 9]),
            signature: Data([10, 11, 12]),
            userHandle: Data([13, 14, 15])
        )

        let body = result.requestBody(client: "ios")
        XCTAssertEqual(body["client"] as? String, "ios")
        let response = try XCTUnwrap(body["response"] as? [String: Any])
        XCTAssertEqual(response["id"] as? String, "AQID")
        let nested = try XCTUnwrap(response["response"] as? [String: Any])
        XCTAssertEqual(nested["authenticatorData"] as? String, "BwgJ")
        XCTAssertEqual(nested["signature"] as? String, "CgsM")
        XCTAssertEqual(nested["userHandle"] as? String, "DQ4P")
    }
}
