// SPDX-License-Identifier: MIT

import CryptoKit
import Foundation

/// RFC 7636 proof key. Nextcloud Social's token endpoint takes `code_verifier`
/// and its discovery document advertises `S256`.
public struct PKCE: Sendable, Hashable {
    public let verifier: String
    public let challenge: String
    public let method = "S256"

    public init() {
        self.init(verifier: Self.randomVerifier())
    }

    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = Self.challenge(for: verifier)
    }

    /// 43–128 characters of unreserved alphabet, per the RFC. 64 bytes of
    /// randomness base64url-encoded lands at 86, comfortably inside.
    public static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        return Data(bytes).base64URLEncodedString()
    }

    public static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

extension Data {
    /// base64url, unpadded — what OAuth wants and what `base64EncodedString`
    /// does not give.
    public func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func randomBase64URL(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        return Data(bytes).base64URLEncodedString()
    }
}
