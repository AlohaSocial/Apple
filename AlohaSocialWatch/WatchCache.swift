// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Observation

/// What the watch last saw, kept in a file of its own so a screen opens on
/// something even where there is no connection at all (docs/09 §4).
///
/// A wrist is the place a phone is most often out of reach and Wi-Fi least
/// often there, and every screen used to open on a spinner that never ended.
/// Each list is one small JSON file in the app's own container: twenty posts
/// or notifications, written after every refresh that worked and read before
/// the next one starts. It is a cache, not a store — nothing in it is ever
/// the only copy of anything.
nonisolated enum WatchCache {
    enum Kind: String, CaseIterable {
        case timeline, mentions, notifications
    }

    /// One list, with whose it is and when it was fetched.
    struct Entry<Item: Codable>: Codable {
        var accountID: UUID
        var updatedAt: Date
        var items: [Item]
    }

    private static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "WatchCache", directoryHint: .isDirectory)
    }

    private static func file(for kind: Kind) -> URL? {
        directory?.appending(path: "\(kind.rawValue).json", directoryHint: .notDirectory)
    }

    /// The list `kind` last held for `accountID`, or nil: another account's
    /// posts are not this account's timeline.
    static func load<Item: Codable>(_ kind: Kind, accountID: UUID) -> Entry<Item>? {
        guard let url = file(for: kind), let data = try? Data(contentsOf: url),
            let entry = try? AlohaJSON.decoder.decode(Entry<Item>.self, from: data),
            entry.accountID == accountID
        else { return nil }
        return entry
    }

    static func save<Item: Codable>(_ entry: Entry<Item>, as kind: Kind) {
        guard let directory, let url = file(for: kind),
            let data = try? AlohaJSON.encoder.encode(entry)
        else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Complete protection is the right class for posts and handles: the
        // watch reads them only while it is on a wrist and unlocked.
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Everything, when the phone signs out or switches account.
    static func clear() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}

extension WatchCache.Entry: Sendable where Item: Sendable {}

/// A list a watch screen shows: the cached copy at once, then the server's
/// answer when it comes, and what to say when it did not.
@MainActor
@Observable
final class WatchFeed<Item: Codable & Sendable & Identifiable> {
    private(set) var items: [Item] = []
    /// When `items` came from the server; nil until anything has.
    private(set) var updatedAt: Date?
    /// True from the start, so an empty list does not say "nothing yet" in
    /// the moment before the first load begins.
    private(set) var isLoading = true
    /// The last refresh failed, so what is on screen is the cache.
    private(set) var isShowingCache = false

    private let kind: WatchCache.Kind
    private var loadedAccount: UUID?

    init(_ kind: WatchCache.Kind) {
        self.kind = kind
    }

    /// Shows the cache first — instantly, from the file — and then asks the
    /// server. A failure keeps the cache on screen and says how old it is.
    func load(accountID: UUID?, fetch: () async throws -> [Item]) async {
        guard let accountID else { return }
        if loadedAccount != accountID {
            loadedAccount = accountID
            let cached: WatchCache.Entry<Item>? = WatchCache.load(kind, accountID: accountID)
            items = cached?.items ?? []
            updatedAt = cached?.updatedAt
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await fetch()
            // The phone may have switched account while the request was out.
            guard loadedAccount == accountID else { return }
            let now = Date()
            items = fresh
            updatedAt = now
            isShowingCache = false
            let entry = WatchCache.Entry(accountID: accountID, updatedAt: now, items: fresh)
            let kind = kind
            // Encoding twenty posts is not free on a watch; it happens off
            // the main thread, after the list has already been drawn.
            Task.detached(priority: .utility) { WatchCache.save(entry, as: kind) }
        } catch {
            isShowingCache = true
        }
    }
}
