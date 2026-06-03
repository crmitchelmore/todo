import Foundation
import CryptoKit

/// A nonce pair for Sign in with Apple. We hand `hashed` to `ASAuthorizationAppleIDRequest.nonce`
/// and keep `raw`; the backend recomputes `sha256(raw)` and checks it against the identity token's
/// `nonce` claim. This binds the Apple assertion to this specific login attempt and blocks replay.
public struct AppleNonce: Sendable {
    public let raw: String
    public let hashed: String

    public init() {
        self.raw = AppleNonce.randomString(length: 32)
        self.hashed = AppleNonce.sha256Hex(raw)
    }

    private static func randomString(length: Int) -> String {
        let charset = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    public static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
