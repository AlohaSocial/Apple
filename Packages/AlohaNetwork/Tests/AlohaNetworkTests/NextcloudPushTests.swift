// SPDX-License-Identifier: MIT

import Foundation
import Security
import Testing

@testable import AlohaNetwork

@Suite("Nextcloud push")
struct NextcloudPushTests {

    @Test("A generated key pair produces a PEM the server can read")
    func keyPairShape() throws {
        let keys = try NextcloudPushKeys.generate()

        #expect(keys.publicKeyPEM.hasPrefix("-----BEGIN PUBLIC KEY-----"))
        #expect(keys.publicKeyPEM.hasSuffix("-----END PUBLIC KEY-----"))
        #expect(keys.privateKeyData.isEmpty == false)

        // Every body line is wrapped at 64 characters, as PEM requires.
        let body = keys.publicKeyPEM.split(separator: "\n").dropFirst().dropLast()
        #expect(body.allSatisfy { $0.count <= 64 })
        #expect(body.count > 1)
    }

    /// The PEM has to be a SubjectPublicKeyInfo, not the PKCS#1 that
    /// `SecKeyCopyExternalRepresentation` hands back — a server given the
    /// wrong one accepts the registration and then cannot encrypt to it.
    @Test("The public key is wrapped as SubjectPublicKeyInfo")
    func publicKeyIsSPKI() throws {
        let keys = try NextcloudPushKeys.generate()
        let base64 = keys.publicKeyPEM
            .split(separator: "\n").dropFirst().dropLast().joined()
        let der = try #require(Data(base64Encoded: base64))

        // SEQUENCE, then the rsaEncryption algorithm identifier.
        #expect(der[0] == 0x30)
        let algorithm: [UInt8] = [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01]
        #expect(der.range(of: Data(algorithm)) != nil)

        // And it has to be something Security can read back as a public key.
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        var error: Unmanaged<CFError>?
        let stripped = der.dropFirst(der.count - 270)  // PKCS#1 tail of a 2048-bit key
        #expect(
            SecKeyCreateWithData(Data(stripped) as CFData, attributes as CFDictionary, &error)
                != nil)
    }

    @Test("A payload encrypted to the device key round-trips")
    func decryptionRoundTrip() throws {
        let keys = try NextcloudPushKeys.generate()

        // Rebuild the public half and encrypt with it, which is what the
        // server does before the proxy delivers it.
        let privateAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        let privateKey = try #require(
            SecKeyCreateWithData(
                keys.privateKeyData as CFData, privateAttributes as CFDictionary, &error))
        let publicKey = try #require(SecKeyCopyPublicKey(privateKey))

        let message = Data(#"{"nid":42,"app":"social","subject":"alice mentioned you"}"#.utf8)
        let ciphertext = try #require(
            SecKeyCreateEncryptedData(
                publicKey, .rsaEncryptionOAEPSHA1, message as CFData, &error) as Data?)

        let decrypted = try keys.decrypt(subject: ciphertext.base64EncodedString())
        #expect(decrypted == message)

        let payload = try JSONDecoder().decode(NextcloudPushPayload.self, from: decrypted)
        #expect(payload.nid == 42)
        #expect(payload.app == "social")
        #expect(payload.isWithdrawal == false)
    }

    /// Servers of different vintages use different padding, so the client tries
    /// OAEP and then PKCS#1 — the official client does the same.
    @Test("PKCS#1 v1.5 padding also decrypts")
    func pkcs1Fallback() throws {
        let keys = try NextcloudPushKeys.generate()

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        let privateKey = try #require(
            SecKeyCreateWithData(keys.privateKeyData as CFData, attributes as CFDictionary, &error))
        let publicKey = try #require(SecKeyCopyPublicKey(privateKey))

        let message = Data(#"{"delete-all":true}"#.utf8)
        let ciphertext = try #require(
            SecKeyCreateEncryptedData(
                publicKey, .rsaEncryptionPKCS1, message as CFData, &error) as Data?)

        let decrypted = try keys.decrypt(subject: ciphertext.base64EncodedString())
        let payload = try JSONDecoder().decode(NextcloudPushPayload.self, from: decrypted)
        #expect(payload.isWithdrawal)
    }

    @Test("Rubbish in the subject is an error, not a crash")
    func malformedSubject() throws {
        let keys = try NextcloudPushKeys.generate()
        #expect(throws: (any Error).self) { try keys.decrypt(subject: "not base64 @@@") }
        #expect(throws: (any Error).self) { try keys.decrypt(subject: "aGVsbG8=") }
    }

    @Test("The proxy default matches the official client's")
    func proxyDefault() {
        #expect(
            NextcloudPush.defaultProxy.absoluteString
                == "https://push-notifications.nextcloud.com")
        // The proxy refuses a registration that does not declare this.
        #expect(NextcloudPush.proxyUserAgent.contains("Strict VoIP"))
    }
}
