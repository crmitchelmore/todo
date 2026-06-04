import Foundation

public struct PasskeyRegistrationOptions: Decodable, Sendable {
    public let challenge: Data
    public let relyingPartyId: String
    public let userName: String
    public let userId: Data

    private enum Outer: String, CodingKey { case options }
    private enum Options: String, CodingKey { case challenge, rp, user }
    private enum RelyingParty: String, CodingKey { case id }
    private enum User: String, CodingKey { case id, name }

    public init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: Outer.self)
        let options = try outer.nestedContainer(keyedBy: Options.self, forKey: .options)
        challenge = try Data(base64URLEncoded: options.decode(String.self, forKey: .challenge))
        let rp = try options.nestedContainer(keyedBy: RelyingParty.self, forKey: .rp)
        relyingPartyId = try rp.decode(String.self, forKey: .id)
        let user = try options.nestedContainer(keyedBy: User.self, forKey: .user)
        userName = try user.decode(String.self, forKey: .name)
        userId = try Data(base64URLEncoded: user.decode(String.self, forKey: .id))
    }
}

public struct PasskeyAuthenticationOptions: Decodable, Sendable {
    public let challenge: Data
    public let relyingPartyId: String

    private enum Outer: String, CodingKey { case options }
    private enum Options: String, CodingKey { case challenge, rpId }

    public init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: Outer.self)
        let options = try outer.nestedContainer(keyedBy: Options.self, forKey: .options)
        challenge = try Data(base64URLEncoded: options.decode(String.self, forKey: .challenge))
        relyingPartyId = try options.decode(String.self, forKey: .rpId)
    }
}

public struct PasskeyRegistrationResult: Encodable, Sendable {
    public let credentialId: Data
    public let clientDataJSON: Data
    public let attestationObject: Data

    public init(credentialId: Data, clientDataJSON: Data, attestationObject: Data) {
        self.credentialId = credentialId
        self.clientDataJSON = clientDataJSON
        self.attestationObject = attestationObject
    }
}

public struct PasskeyAuthenticationResult: Encodable, Sendable {
    public let credentialId: Data
    public let clientDataJSON: Data
    public let authenticatorData: Data
    public let signature: Data
    public let userHandle: Data?

    public init(credentialId: Data, clientDataJSON: Data, authenticatorData: Data, signature: Data, userHandle: Data?) {
        self.credentialId = credentialId
        self.clientDataJSON = clientDataJSON
        self.authenticatorData = authenticatorData
        self.signature = signature
        self.userHandle = userHandle
    }
}

extension PasskeyRegistrationResult {
    func requestBody() -> [String: Any] {
        let id = credentialId.base64URLEncodedString()
        return [
            "response": [
                "id": id,
                "rawId": id,
                "type": "public-key",
                "clientExtensionResults": [:],
                "response": [
                    "clientDataJSON": clientDataJSON.base64URLEncodedString(),
                    "attestationObject": attestationObject.base64URLEncodedString()
                ]
            ]
        ]
    }
}

extension PasskeyAuthenticationResult {
    func requestBody(client: String) -> [String: Any] {
        let id = credentialId.base64URLEncodedString()
        var response: [String: Any] = [
            "clientDataJSON": clientDataJSON.base64URLEncodedString(),
            "authenticatorData": authenticatorData.base64URLEncodedString(),
            "signature": signature.base64URLEncodedString()
        ]
        if let userHandle {
            response["userHandle"] = userHandle.base64URLEncodedString()
        }
        return [
            "client": client,
            "response": [
                "id": id,
                "rawId": id,
                "type": "public-key",
                "clientExtensionResults": [:],
                "response": response
            ]
        ]
    }
}

extension Data {
    init(base64URLEncoded value: String) throws {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        guard let data = Data(base64Encoded: base64) else {
            throw CaptureError.auth("invalid passkey challenge")
        }
        self = data
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
