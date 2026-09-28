// SPDX-License-Identifier: MIT

import AlohaModels
import CryptoKit
import Foundation

/// Web Push subscription and payload decryption (RFC 8291).
///
/// **Dormant against Nextcloud Social**, which sends an empty `vapid_key` —
/// that empty string is the server saying not to offer it. Live against real
/// Mastodon, which is why it is written rather than deferred (docs/08 §6).
public struct WebPushKeys: Sendable, Codable, Hashable {
    /// The P-256 public key, uncompressed, base64url.
    public var publicKey: String
    /// The private key, kept in the Keychain alongside the token.
    public var privateKeyData: Data
    /// 16 random bytes shared with the server.
    public var authSecret: String

    public init(publicKey: String, privateKeyData: Data, authSecret: String) {
        self.publicKey = publicKey
        self.privateKeyData = privateKeyData
        self.authSecret = authSecret
    }

    public static func generate() -> WebPushKeys {
        let privateKey = P256.KeyAgreement.PrivateKey()
        var auth = [UInt8](repeating: 0, count: 16)
        for index in auth.indices { auth[index] = UInt8.random(in: .min ... .max) }

        return WebPushKeys(
            publicKey: privateKey.publicKey.x963Representation.base64URLEncodedString(),
            privateKeyData: privateKey.rawRepresentation,
            authSecret: Data(auth).base64URLEncodedString())
    }
}

/// Which kinds the server should push. Mirrors the app's local-notification
/// toggles so the two cannot disagree.
public struct WebPushPreferences: Sendable, Hashable {
    public var mention = true
    public var status = true
    public var reblog = true
    public var follow = true
    public var followRequest = true
    public var favourite = true
    public var poll = true
    public var update = true

    public init() {}

    var formItems: [URLQueryItem] {
        [
            ("mention", mention), ("status", status), ("reblog", reblog),
            ("follow", follow), ("follow_request", followRequest),
            ("favourite", favourite), ("poll", poll), ("update", update),
        ].map { URLQueryItem(name: "data[alerts][\($0.0)]", value: $0.1 ? "true" : "false") }
    }
}

extension Endpoint {
    public enum push {
        /// `POST /api/v1/push/subscription`. A 404 here is the server saying it
        /// has no Web Push, which is the normal case on Nextcloud Social.
        public static func subscribe(
            endpoint: String, keys: WebPushKeys, preferences: WebPushPreferences
        ) -> Endpoint {
            Endpoint(
                method: .post, path: "api/v1/push/subscription",
                body: .form(
                    [
                        URLQueryItem(name: "subscription[endpoint]", value: endpoint),
                        URLQueryItem(name: "subscription[keys][p256dh]", value: keys.publicKey),
                        URLQueryItem(name: "subscription[keys][auth]", value: keys.authSecret),
                    ] + preferences.formItems))
        }

        public static var unsubscribe: Endpoint {
            Endpoint(method: .delete, path: "api/v1/push/subscription")
        }

        public static var current: Endpoint {
            Endpoint(path: "api/v1/push/subscription")
        }
    }
}

public struct PushSubscription: Codable, Sendable, Hashable {
    @FlexibleID public var id: String
    public var endpoint: String
    public var serverKey: String

    enum CodingKeys: String, CodingKey {
        case id, endpoint
        case serverKey = "server_key"
    }
}

/// RFC 8291 `aes128gcm` decryption, for the notification service extension.
///
/// Without this a push arrives as "New activity" and nothing else; with it the
/// notification carries the real content (docs/08 §6).
public enum WebPushDecryptor {

    public enum DecryptionError: Error, Sendable {
        case malformedPayload
        case badKey
        case decryptionFailed
    }

    /// - Parameter payload: the raw `aes128gcm` body.
    public static func decrypt(payload: Data, keys: WebPushKeys) throws -> Data {
        // Header: salt (16) | record size (4) | key id length (1) | key id.
        guard payload.count > 21 else { throw DecryptionError.malformedPayload }

        let salt = payload.prefix(16)
        let keyIDLength = Int(payload[payload.startIndex + 20])
        let headerLength = 21 + keyIDLength
        guard payload.count > headerLength else { throw DecryptionError.malformedPayload }

        let senderKeyData = payload[
            payload.startIndex.advanced(by: 21)..<payload.startIndex.advanced(by: headerLength)]
        let ciphertext = payload[payload.startIndex.advanced(by: headerLength)...]

        guard
            let privateKey = try? P256.KeyAgreement.PrivateKey(
                rawRepresentation: keys.privateKeyData),
            let senderKey = try? P256.KeyAgreement.PublicKey(
                x963Representation: Data(senderKeyData))
        else { throw DecryptionError.badKey }

        let shared = try privateKey.sharedSecretFromKeyAgreement(with: senderKey)

        guard let authSecret = Data(base64URLEncoded: keys.authSecret) else {
            throw DecryptionError.badKey
        }

        // The key info is the literal, both public keys, and a null separator,
        // exactly as RFC 8291 §3.4 specifies.
        var keyInfo = Data("WebPush: info\0".utf8)
        keyInfo.append(privateKey.publicKey.x963Representation)
        keyInfo.append(Data(senderKeyData))

        let ikm = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: authSecret, sharedInfo: keyInfo, outputByteCount: 32)

        let contentKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm, salt: Data(salt),
            info: Data("Content-Encoding: aes128gcm\0".utf8), outputByteCount: 16)
        let nonce = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm, salt: Data(salt),
            info: Data("Content-Encoding: nonce\0".utf8), outputByteCount: 12)

        let nonceBytes = nonce.withUnsafeBytes { Data($0) }

        guard
            let sealed = try? AES.GCM.SealedBox(
                combined: nonceBytes + Data(ciphertext)),
            let plaintext = try? AES.GCM.open(sealed, using: contentKey)
        else { throw DecryptionError.decryptionFailed }

        // Strip the padding delimiter the RFC appends.
        guard let delimiter = plaintext.lastIndex(where: { $0 == 0x02 || $0 == 0x01 }) else {
            return plaintext
        }
        return plaintext.prefix(upTo: delimiter)
    }
}

extension Data {
    public init?(base64URLEncoded string: String) {
        var value =
            string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value.append("=") }
        self.init(base64Encoded: value)
    }
}
