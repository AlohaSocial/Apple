// SPDX-License-Identifier: MIT

import AlohaNetwork
import Foundation

/// The Apple TV's one signed-in account, where both the TV app and its Top
/// Shelf extension can read it.
///
/// The TV app kept its account in its own `UserDefaults` and a private
/// Keychain item, which an extension cannot see. It now keeps them in the app
/// group and the shared Keychain group; a sign-in made by an older build is
/// moved across the first time the app reads it, so nobody signs in twice.
public struct TVAccount: Sendable, Equatable {
    public var id: UUID
    public var apiBase: URL
    public var token: String

    public init(id: UUID, apiBase: URL, token: String) {
        self.id = id
        self.apiBase = apiBase
        self.token = token
    }
}

public struct TVAccountStore: Sendable {
    static let accountKey = "aloha.tv.account"
    static let apiBaseKey = "aloha.tv.apiBase"

    /// `UserDefaults` is thread-safe by contract; the compiler cannot see it.
    nonisolated(unsafe) private let shared: UserDefaults
    nonisolated(unsafe) private let legacy: UserDefaults
    private let sharedCredentials: CredentialStore
    private let legacyCredentials: CredentialStore

    public init(
        shared: UserDefaults = AppGroup.defaults, legacy: UserDefaults = .standard,
        sharedCredentials: CredentialStore = .shared,
        legacyCredentials: CredentialStore = CredentialStore()
    ) {
        self.shared = shared
        self.legacy = legacy
        self.sharedCredentials = sharedCredentials
        self.legacyCredentials = legacyCredentials
    }

    /// The account, from the shared stores.
    ///
    /// With `adoptingLegacy`, which only the app passes, an account found in
    /// the app's own stores is copied into the shared ones first. The
    /// extension never does: its own stores were always empty, and a read
    /// there must not write anything.
    public func load(adoptingLegacy: Bool = false) -> TVAccount? {
        if let account = read(defaults: shared, credentials: sharedCredentials) {
            return account
        }
        guard adoptingLegacy,
            let account = read(defaults: legacy, credentials: legacyCredentials)
        else { return nil }
        // Kept where it was as well: an older build installed again still
        // finds its sign-in.
        try? save(account)
        return account
    }

    public func save(_ account: TVAccount) throws {
        try sharedCredentials.setToken(account.token, for: account.id)
        shared.set(account.id.uuidString, forKey: Self.accountKey)
        shared.set(account.apiBase, forKey: Self.apiBaseKey)
    }

    private func read(defaults: UserDefaults, credentials: CredentialStore) -> TVAccount? {
        guard let raw = defaults.string(forKey: Self.accountKey),
            let id = UUID(uuidString: raw),
            let base = defaults.url(forKey: Self.apiBaseKey),
            let token = (try? credentials.token(for: id)) ?? nil
        else { return nil }
        return TVAccount(id: id, apiBase: base, token: token)
    }
}
