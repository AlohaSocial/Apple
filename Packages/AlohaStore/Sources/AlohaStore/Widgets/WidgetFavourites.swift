// SPDX-License-Identifier: MIT

import AlohaNetwork
import Foundation

/// What a widget's favourite button did, until the cached post catches up.
///
/// A widget redraws from what it can read the moment its intent returns, and
/// a mention row has no cached post to rewrite — only the notification that
/// points at it. So the tap is written here first, read before the store, and
/// forgotten after a day, by which time the next sync has the server's word.
public enum WidgetFavourites {
    /// How long a tap outranks the cache.
    public static let lifetime = WidgetTapLedger.lifetime

    static let ledger = WidgetTapLedger(key: "aloha.widgetFavourites")

    /// The state a tap left for this post, while it is still fresh.
    public static func state(
        statusID: String, accountID: UUID, now: Date = Date(),
        in defaults: UserDefaults = AppGroup.defaults
    ) -> Bool? {
        ledger.state(statusID: statusID, accountID: accountID, now: now, in: defaults)
    }

    public static func set(
        _ favourited: Bool, statusID: String, accountID: UUID, now: Date = Date(),
        in defaults: UserDefaults = AppGroup.defaults
    ) {
        ledger.set(favourited, statusID: statusID, accountID: accountID, now: now, in: defaults)
    }

    /// Takes a tap back: the server refused it, so the cache is right again.
    public static func clear(
        statusID: String, accountID: UUID, in defaults: UserDefaults = AppGroup.defaults
    ) {
        ledger.clear(statusID: statusID, accountID: accountID, in: defaults)
    }

    /// Forgets every tap made for one account, which has signed out.
    public static func removeAll(
        accountID: UUID, in defaults: UserDefaults = AppGroup.defaults
    ) {
        ledger.removeAll(accountID: accountID, in: defaults)
    }
}

/// What a widget's bookmark button did, until the cached post catches up —
/// the favourite button's ledger, under its own key.
public enum WidgetBookmarks {
    static let ledger = WidgetTapLedger(key: "aloha.widgetBookmarks")

    public static func state(
        statusID: String, accountID: UUID, now: Date = Date(),
        in defaults: UserDefaults = AppGroup.defaults
    ) -> Bool? {
        ledger.state(statusID: statusID, accountID: accountID, now: now, in: defaults)
    }

    public static func set(
        _ bookmarked: Bool, statusID: String, accountID: UUID, now: Date = Date(),
        in defaults: UserDefaults = AppGroup.defaults
    ) {
        ledger.set(bookmarked, statusID: statusID, accountID: accountID, now: now, in: defaults)
    }

    public static func clear(
        statusID: String, accountID: UUID, in defaults: UserDefaults = AppGroup.defaults
    ) {
        ledger.clear(statusID: statusID, accountID: accountID, in: defaults)
    }

    public static func removeAll(
        accountID: UUID, in defaults: UserDefaults = AppGroup.defaults
    ) {
        ledger.removeAll(accountID: accountID, in: defaults)
    }
}

/// A per-post on/off a widget button set, kept in the shared defaults for a
/// day under one key.
public struct WidgetTapLedger: Sendable {
    public static let lifetime: TimeInterval = 86_400

    let key: String

    struct Entry: Codable, Equatable {
        var on: Bool
        var at: Date

        enum CodingKeys: String, CodingKey {
            // The favourites ledger wrote `favourited` before it was shared.
            case on = "favourited"
            case at
        }
    }

    func state(statusID: String, accountID: UUID, now: Date, in defaults: UserDefaults) -> Bool? {
        guard let entry = entries(in: defaults)[entryKey(statusID, accountID)],
            now.timeIntervalSince(entry.at) < Self.lifetime
        else { return nil }
        return entry.on
    }

    func set(_ on: Bool, statusID: String, accountID: UUID, now: Date, in defaults: UserDefaults) {
        var all = entries(in: defaults).filter {
            now.timeIntervalSince($0.value.at) < Self.lifetime
        }
        all[entryKey(statusID, accountID)] = Entry(on: on, at: now)
        save(all, in: defaults)
    }

    func clear(statusID: String, accountID: UUID, in defaults: UserDefaults) {
        var all = entries(in: defaults)
        guard all.removeValue(forKey: entryKey(statusID, accountID)) != nil else { return }
        save(all, in: defaults)
    }

    func removeAll(accountID: UUID, in defaults: UserDefaults) {
        let prefix = "\(accountID.uuidString)/"
        let all = entries(in: defaults)
        let kept = all.filter { !$0.key.hasPrefix(prefix) }
        guard kept.count != all.count else { return }
        save(kept, in: defaults)
    }

    private func entryKey(_ statusID: String, _ accountID: UUID) -> String {
        "\(accountID.uuidString)/\(statusID)"
    }

    private func entries(in defaults: UserDefaults) -> [String: Entry] {
        guard let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }

    private func save(_ entries: [String: Entry], in defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}
