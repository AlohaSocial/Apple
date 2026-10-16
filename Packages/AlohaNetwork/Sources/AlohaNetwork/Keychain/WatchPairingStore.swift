// SPDX-License-Identifier: MIT

import Foundation

/// Where the watch keeps what the phone handed it: the watch app writes it,
/// and its complications read it to ask the server for counts on their own.
///
/// The item lives in the shared Keychain access group, which is the only
/// place a widget extension can read a secret its app wrote. Builds before
/// the watch had complications wrote it to the app's private group instead;
/// `load()` moves such an item over the first time it finds one, so an
/// update keeps the pairing rather than showing "Not paired yet" until the
/// phone next sends it.
public struct WatchPairingStore: Sendable {
    static let service = "social.aloha.app.watch"
    static let account = "credentials"

    /// The shared group, or `nil` where Keychain sharing is off.
    private let shared: KeychainStore
    /// No group in the query: it matches the item wherever it was written,
    /// which is how an older build's private copy is found and removed.
    private let anywhere: KeychainStore
    private let isShared: Bool

    public init(accessGroup: String? = AppGroup.keychainAccessGroup, inMemory: Bool = false) {
        shared = KeychainStore(service: Self.service, accessGroup: accessGroup, inMemory: inMemory)
        anywhere = KeychainStore(service: Self.service, inMemory: inMemory)
        isShared = accessGroup != nil
    }

    public func load() -> WatchPairing? {
        if let raw = (try? shared.get(Self.account)) ?? nil {
            return Self.decode(raw)
        }
        guard isShared, let raw = (try? anywhere.get(Self.account)) ?? nil,
            let pairing = Self.decode(raw)
        else { return nil }
        // Delete first: a query without a group would also match the shared
        // copy once it exists. Losing the item between the two calls costs a
        // pairing the phone sends again on its next context update.
        try? anywhere.remove(Self.account)
        save(pairing)
        return pairing
    }

    /// Same accessibility class as the phone's: this device only, never
    /// iCloud Keychain and never an encrypted backup onto another device.
    public func save(_ pairing: WatchPairing) {
        guard let data = try? JSONEncoder().encode(pairing),
            let raw = String(data: data, encoding: .utf8)
        else { return }
        try? shared.set(raw, for: Self.account)
    }

    /// Every copy, shared or not: a stale private one would come back on the
    /// next `load()`.
    public func remove() {
        try? shared.remove(Self.account)
        try? anywhere.remove(Self.account)
    }

    private static func decode(_ raw: String) -> WatchPairing? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WatchPairing.self, from: data)
    }
}
