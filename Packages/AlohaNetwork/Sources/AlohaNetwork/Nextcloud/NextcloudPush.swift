// SPDX-License-Identifier: MIT

import CryptoKit
import Foundation
import OSLog
import Security

/// Push through **Nextcloud's own proxy**, the way the official client does it
/// (`nextcloud/ios`, `NCPushNotification.swift`).
///
/// This is not Mastodon Web Push. Nextcloud Social serves no `/api/v1/push/*`
/// and announces an empty `vapid_key`; but the Nextcloud *underneath* it has
/// the notifications app, and that talks to a proxy which does speak APNs. So
/// where the person has connected their Nextcloud, this is a real push path —
/// and it is the reason the polling engine can stand down.
///
/// The flow, in order:
/// 1. RSA-2048 key pair, kept in the Keychain.
/// 2. `POST /ocs/v2.php/apps/notifications/api/v2/push` with the SHA-512 of the
///    APNs token, the public key as PEM, and the proxy's address. Answers a
///    device identifier, a signature over it, and the server's own public key.
/// 3. `POST {proxy}/devices?format=json` with the APNs token and those three.
/// 4. Each push arrives with a `subject` that is RSA-encrypted to the device
///    key; decrypting it is what turns "Nextcloud notification" into content.
public struct NextcloudPush: Sendable {
    /// What the official client defaults to.
    public static let defaultProxy = URL(string: "https://push-notifications.nextcloud.com")!

    /// The proxy refuses a registration whose user agent does not declare this.
    static let proxyUserAgent = AlohaUserAgent.value + " (Strict VoIP)"

    private let transport: any HTTPTransport
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "ncpush")

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public struct Registration: Sendable, Hashable, Codable {
        public var deviceIdentifier: String
        public var signature: String
        /// The **server's** public key, handed on to the proxy.
        public var serverPublicKey: String
        public var proxy: URL
    }

    public enum PushError: Error, Sendable {
        case notificationsAppUnavailable
        case malformedResponse
        case proxyRefused(Int)
        case keyGenerationFailed
    }

    // MARK: - Subscribing

    public func subscribe(
        credentials: NextcloudLoginFlow.Credentials,
        deviceToken: Data,
        keys: NextcloudPushKeys,
        proxy: URL = NextcloudPush.defaultProxy
    ) async throws -> Registration {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        let tokenHash = SHA512.hash(data: Data(tokenString.utf8))
            .map { String(format: "%02x", $0) }.joined()

        let registration = try await registerWithServer(
            credentials: credentials, pushTokenHash: tokenHash,
            devicePublicKey: keys.publicKeyPEM, proxy: proxy)

        try await registerWithProxy(
            proxy: proxy, pushToken: tokenString, registration: registration)

        logger.info("registered for nextcloud push")
        return registration
    }

    private func registerWithServer(
        credentials: NextcloudLoginFlow.Credentials,
        pushTokenHash: String,
        devicePublicKey: String,
        proxy: URL
    ) async throws -> Registration {
        var request = URLRequest(
            url: credentials.server.appending(
                path: "ocs/v2.php/apps/notifications/api/v2/push"))
        request.httpMethod = "POST"
        request.setValue(credentials.basicAuthorization, forHTTPHeaderField: "Authorization")
        // Every OCS route refuses a request without this.
        request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "application/x-www-form-urlencoded; charset=utf-8",
            forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "pushTokenHash", value: pushTokenHash),
            URLQueryItem(name: "devicePublicKey", value: devicePublicKey),
            URLQueryItem(name: "proxyServer", value: proxy.absoluteString),
        ]
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await transport.send(request)
        // A Nextcloud without the notifications app answers 404 here, which is
        // a normal answer rather than a failure.
        guard response.statusCode != 404 else { throw PushError.notificationsAppUnavailable }
        guard (200..<300).contains(response.statusCode) else {
            throw PushError.proxyRefused(response.statusCode)
        }

        struct Envelope: Decodable {
            struct OCS: Decodable {
                struct Payload: Decodable {
                    let deviceIdentifier: String
                    let signature: String
                    let publicKey: String
                }
                let data: Payload
            }
            let ocs: OCS
        }

        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw PushError.malformedResponse
        }

        return Registration(
            deviceIdentifier: envelope.ocs.data.deviceIdentifier,
            signature: envelope.ocs.data.signature,
            serverPublicKey: envelope.ocs.data.publicKey,
            proxy: proxy)
    }

    private func registerWithProxy(
        proxy: URL, pushToken: String, registration: Registration
    ) async throws {
        var components = URLComponents(
            url: proxy.appending(path: "devices"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "format", value: "json")]
        guard let url = components?.url else { throw PushError.malformedResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.proxyUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            "application/x-www-form-urlencoded; charset=utf-8",
            forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "pushToken", value: pushToken),
            URLQueryItem(name: "deviceIdentifier", value: registration.deviceIdentifier),
            URLQueryItem(name: "deviceIdentifierSignature", value: registration.signature),
            URLQueryItem(name: "userPublicKey", value: registration.serverPublicKey),
        ]
        request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)

        let (_, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw PushError.proxyRefused(response.statusCode)
        }
    }

    // MARK: - Unsubscribing

    public func unsubscribe(
        credentials: NextcloudLoginFlow.Credentials, registration: Registration
    ) async {
        var serverRequest = URLRequest(
            url: credentials.server.appending(
                path: "ocs/v2.php/apps/notifications/api/v2/push"))
        serverRequest.httpMethod = "DELETE"
        serverRequest.setValue(
            credentials.basicAuthorization, forHTTPHeaderField: "Authorization")
        serverRequest.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        _ = try? await transport.send(serverRequest)

        var proxyRequest = URLRequest(url: registration.proxy.appending(path: "devices"))
        proxyRequest.httpMethod = "DELETE"
        proxyRequest.setValue(Self.proxyUserAgent, forHTTPHeaderField: "User-Agent")
        proxyRequest.setValue(
            "application/x-www-form-urlencoded; charset=utf-8",
            forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "deviceIdentifier", value: registration.deviceIdentifier),
            URLQueryItem(name: "deviceIdentifierSignature", value: registration.signature),
            URLQueryItem(name: "userPublicKey", value: registration.serverPublicKey),
        ]
        proxyRequest.httpBody = Data((body.percentEncodedQuery ?? "").utf8)
        _ = try? await transport.send(proxyRequest)
    }
}

/// The device's RSA-2048 key pair.
///
/// RSA rather than the P-256 the Mastodon Web Push path uses, because that is
/// what the Nextcloud notifications app and its proxy speak.
public struct NextcloudPushKeys: Sendable, Hashable, Codable {
    /// PEM `SubjectPublicKeyInfo`, which is the form the server expects.
    public var publicKeyPEM: String
    /// PKCS#1 `RSAPrivateKey`, kept in the Keychain.
    public var privateKeyData: Data

    public init(publicKeyPEM: String, privateKeyData: Data) {
        self.publicKeyPEM = publicKeyPEM
        self.privateKeyData = privateKeyData
    }

    public static func generate() throws -> NextcloudPushKeys {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
            let publicKey = SecKeyCopyPublicKey(privateKey),
            let privateData = SecKeyCopyExternalRepresentation(privateKey, &error) as Data?,
            let publicData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?
        else { throw NextcloudPush.PushError.keyGenerationFailed }

        return NextcloudPushKeys(
            publicKeyPEM: RSAKeyEncoding.publicKeyPEM(fromPKCS1: publicData),
            privateKeyData: privateData)
    }

    /// Decrypts a push's `subject`.
    ///
    /// The official client tries OAEP first and falls back to PKCS#1 v1.5,
    /// because servers of different vintages use different padding — and a
    /// notification that cannot be decrypted is one that says nothing.
    public func decrypt(subject: String) throws -> Data {
        guard let payload = Data(base64Encoded: subject) else {
            throw NextcloudPush.PushError.malformedResponse
        }

        // An RSA-2048 block is exactly 256 bytes. Without this check Security
        // will happily "decrypt" a short input and hand back garbage, which
        // would surface as a notification full of nonsense.
        guard payload.count == 256 else { throw NextcloudPush.PushError.malformedResponse }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048,
        ]

        var error: Unmanaged<CFError>?
        guard
            let key = SecKeyCreateWithData(
                privateKeyData as CFData, attributes as CFDictionary, &error)
        else { throw NextcloudPush.PushError.keyGenerationFailed }

        for algorithm in [SecKeyAlgorithm.rsaEncryptionOAEPSHA1, .rsaEncryptionPKCS1] {
            if let plaintext = SecKeyCreateDecryptedData(
                key, algorithm, payload as CFData, &error) as Data?
            {
                return plaintext
            }
        }
        throw NextcloudPush.PushError.malformedResponse
    }
}

/// What a decrypted push carries.
public struct NextcloudPushPayload: Codable, Sendable, Hashable {
    public var nid: Int?
    public var app: String?
    public var subject: String?
    public var type: String?
    public var id: String?
    /// `true` when the server is telling the client to withdraw a notification
    /// it already showed.
    public var delete: Bool?
    public var deleteAll: Bool?

    enum CodingKeys: String, CodingKey {
        case nid, app, subject, type, id, delete
        case deleteAll = "delete-all"
    }

    public var isWithdrawal: Bool { delete == true || deleteAll == true }
}

/// Converting between the two RSA key encodings Security and OpenSSL use.
enum RSAKeyEncoding {
    /// `SecKeyCopyExternalRepresentation` gives a PKCS#1 `RSAPublicKey`;
    /// Nextcloud wants a PEM `SubjectPublicKeyInfo`, which is that wrapped in
    /// an algorithm identifier. Writing the wrapper by hand avoids a
    /// dependency for thirty bytes of DER.
    static func publicKeyPEM(fromPKCS1 pkcs1: Data) -> String {
        // AlgorithmIdentifier for rsaEncryption, with its NULL parameters.
        let algorithm: [UInt8] = [
            0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
            0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00,
        ]

        var bitString = Data([0x00])
        bitString.append(pkcs1)

        var body = Data(algorithm)
        body.append(contentsOf: derTagged(0x03, bitString))

        let spki = Data(derTagged(0x30, body))
        return pemWrapped(spki, label: "PUBLIC KEY")
    }

    private static func derTagged(_ tag: UInt8, _ contents: Data) -> [UInt8] {
        var out: [UInt8] = [tag]
        let count = contents.count

        if count < 0x80 {
            out.append(UInt8(count))
        } else {
            var length = count
            var bytes: [UInt8] = []
            while length > 0 {
                bytes.insert(UInt8(length & 0xff), at: 0)
                length >>= 8
            }
            out.append(0x80 | UInt8(bytes.count))
            out.append(contentsOf: bytes)
        }

        out.append(contentsOf: contents)
        return out
    }

    static func pemWrapped(_ der: Data, label: String) -> String {
        let base64 = der.base64EncodedString()
        var lines: [String] = ["-----BEGIN \(label)-----"]
        var index = base64.startIndex
        while index < base64.endIndex {
            let end =
                base64.index(index, offsetBy: 64, limitedBy: base64.endIndex)
                ?? base64.endIndex
            lines.append(String(base64[index..<end]))
            index = end
        }
        lines.append("-----END \(label)-----")
        return lines.joined(separator: "\n")
    }
}
