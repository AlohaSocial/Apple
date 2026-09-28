// SPDX-License-Identifier: MIT

import Foundation
import Security

/// Tokens, client ids and client secrets.
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` is deliberate:
/// `ThisDeviceOnly` keeps tokens out of iCloud Keychain and out of an encrypted
/// backup restored onto a different device (docs/03 §5). The access group lets
/// the share extension and widgets read what the app wrote.
public struct KeychainStore: Sendable {
    public static let tokenService = "com.nextcloud.alohasocial.token"
    public static let clientService = "com.nextcloud.alohasocial.client"

    private let service: String
    private let accessGroup: String?
    private let isInMemory: Bool

    /// `inMemory` exists for one reason: an unsigned simulator build has no
    /// `application-identifier` entitlement, so every keychain call returns
    /// `errSecMissingEntitlement` and the app cannot hold a token. That is what
    /// kept the UI tours out of CI, which cannot sign.
    public init(service: String, accessGroup: String? = nil, inMemory: Bool = false) {
        self.service = service
        self.accessGroup = accessGroup
        self.isInMemory = inMemory
    }

    /// Process-lifetime storage, keyed the same way the keychain is.
    private static let memory = MemoryStore()

    private final class MemoryStore: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: String] = [:]

        func get(_ key: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return values[key]
        }
        func set(_ value: String, for key: String) {
            lock.lock()
            defer { lock.unlock() }
            values[key] = value
        }
        func remove(_ key: String) {
            lock.lock()
            defer { lock.unlock() }
            values[key] = nil
        }
    }

    private func memoryKey(_ account: String) -> String { "\(service)\u{1}\(account)" }

    /// `$(AppIdentifierPrefix)` is expanded in the entitlement but not in a
    /// Swift literal, so the team prefix is read back from the app's own
    /// keychain item at runtime.
    private static func qualified(_ group: String) -> String {
        if group.contains("."), group.first?.isNumber == true { return group }
        guard let prefix = teamPrefix else { return group }
        return prefix + group
    }

    private static let teamPrefix: String? = {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "com.nextcloud.alohasocial.prefix-probe",
            kSecAttrService as String: "com.nextcloud.alohasocial.prefix-probe",
            kSecReturnAttributes as String: true,
        ]
        var item: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            var add = query
            add.removeValue(forKey: kSecReturnAttributes as String)
            add[kSecValueData as String] = Data()
            SecItemAdd(add as CFDictionary, nil)
            status = SecItemCopyMatching(query as CFDictionary, &item)
        }
        guard status == errSecSuccess,
            let attributes = item as? [String: Any],
            let group = attributes[kSecAttrAccessGroup as String] as? String,
            let dot = group.firstIndex(of: ".")
        else { return nil }
        return String(group[...dot])
    }()

    public enum KeychainError: Error, Sendable {
        case unexpectedStatus(OSStatus)
        case malformedData
    }

    /// `errSecMissingEntitlement`: the build's profile does not grant the
    /// access group. Happens on every unsigned build and on any App ID without
    /// Keychain Sharing — and it used to make sign-in fail silently.
    private static let missingEntitlement: OSStatus = -34018

    private func baseQuery(account: String, useGroup: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if useGroup, let accessGroup {
            query[kSecAttrAccessGroup as String] = Self.qualified(accessGroup)
        }
        return query
    }

    /// Runs `operation` with the access group, and again without it if the
    /// entitlement is missing. Sharing with extensions is lost in that case;
    /// the app itself keeps working, which is the right trade.
    private func withGroupFallback<T>(
        _ operation: (_ useGroup: Bool) throws -> T
    ) throws -> T {
        do {
            return try operation(accessGroup != nil)
        } catch KeychainError.unexpectedStatus(let status)
            where status == Self.missingEntitlement && accessGroup != nil
        {
            return try operation(false)
        }
    }

    public func set(_ value: String, for account: String) throws {
        if isInMemory {
            Self.memory.set(value, for: memoryKey(account))
            return
        }
        try withGroupFallback { useGroup in
            let data = Data(value.utf8)
            var query = baseQuery(account: account, useGroup: useGroup)

            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]

            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if updateStatus == errSecSuccess { return }
            guard updateStatus == errSecItemNotFound else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }

            query.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        }
    }

    public func get(_ account: String) throws -> String? {
        if isInMemory { return Self.memory.get(memoryKey(account)) }
        // The closure's result type was inferred from a single-expression body
        // before the in-memory branch was added; it needs saying now.
        return try withGroupFallback { useGroup -> String? in
            var query = baseQuery(account: account, useGroup: useGroup)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.malformedData
            }
            return value
        }
    }

    public func remove(_ account: String) throws {
        if isInMemory {
            Self.memory.remove(memoryKey(account))
            return
        }
        try withGroupFallback { useGroup in
            let status = SecItemDelete(
                baseQuery(account: account, useGroup: useGroup) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unexpectedStatus(status)
            }
        }
    }
}

/// The OAuth client registration for one instance host.
///
/// Cached per host and reused for every subsequent account on that host — which
/// is only safe because Nextcloud Social moved authorisations to a table of
/// their own, so one app row holds many tokens.
public struct ClientRegistration: Codable, Sendable, Hashable {
    public var host: String
    public var clientID: String
    public var clientSecret: String
    public var redirectURI: String
    public var registeredAt: Date

    public init(
        host: String, clientID: String, clientSecret: String,
        redirectURI: String = OAuthService.redirectURI, registeredAt: Date = Date()
    ) {
        self.host = host
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.registeredAt = registeredAt
    }
}

/// Reads and writes both kinds of secret, and is the only thing that does.
public struct CredentialStore: Sendable {
    private let tokens: KeychainStore
    private let clients: KeychainStore

    public init(accessGroup: String? = nil, inMemory: Bool = false) {
        tokens = KeychainStore(
            service: KeychainStore.tokenService, accessGroup: accessGroup, inMemory: inMemory)
        clients = KeychainStore(
            service: KeychainStore.clientService, accessGroup: accessGroup, inMemory: inMemory)
    }

    /// Keyed by the account's client-generated UUID, never by the handle — a
    /// handle can change, and a key that moves loses the token behind it.
    public func token(for accountID: UUID) throws -> String? {
        try tokens.get(accountID.uuidString)
    }

    public func setToken(_ token: String, for accountID: UUID) throws {
        try tokens.set(token, for: accountID.uuidString)
    }

    public func removeToken(for accountID: UUID) throws {
        try tokens.remove(accountID.uuidString)
    }

    public func registration(forHost host: String) throws -> ClientRegistration? {
        guard let raw = try clients.get(host.lowercased()),
            let data = raw.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(ClientRegistration.self, from: data)
    }

    public func setRegistration(_ registration: ClientRegistration) throws {
        let data = try JSONEncoder().encode(registration)
        guard let raw = String(data: data, encoding: .utf8) else { return }
        try clients.set(raw, for: registration.host.lowercased())
    }

    public func removeRegistration(forHost host: String) throws {
        try clients.remove(host.lowercased())
    }

    /// The Web Push key pair lives beside the token, under the same
    /// `ThisDeviceOnly` accessibility class — a push key that syncs is a push
    /// key another device can decrypt with.
    public func pushKeys(for accountID: UUID) throws -> String? {
        try tokens.get("push-\(accountID.uuidString)")
    }

    public func setPushKeys(_ keys: String, for accountID: UUID) throws {
        try tokens.set(keys, for: "push-\(accountID.uuidString)")
    }

    public func removePushKeys(for accountID: UUID) throws {
        try tokens.remove("push-\(accountID.uuidString)")
    }

    func nextcloudRaw(for accountID: UUID) throws -> String? {
        try tokens.get("nextcloud-\(accountID.uuidString)")
    }

    func setNextcloudRaw(_ value: String, for accountID: UUID) throws {
        try tokens.set(value, for: "nextcloud-\(accountID.uuidString)")
    }

    public func removeNextcloudCredentials(for accountID: UUID) throws {
        try tokens.remove("nextcloud-\(accountID.uuidString)")
    }
}
