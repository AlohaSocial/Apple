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
    public static let lifetime: TimeInterval = 86_400

    static let key = "aloha.widgetFavourites"

    struct Entry: Codable, Equatable {
        var favourited: Bool
        var at: Date
    }

    /// The state a tap left for this post, while it is still fresh.
    public static func state(
        statusID: String, accountID: UUID, now: Date = Date(),
        in defaults: UserDefaults = AppGroup.defaults
    ) -> Bool? {
        guard let entry = entries(in: defaults)[entryKey(statusID, accountID)],
            now.timeIntervalSince(entry.at) < lifetime
        else { return nil }
        return entry.favourited
    }

    public static func set(
        _ favourited: Bool, statusID: String, accountID: UUID, now: Date = Date(),
        in defaults: UserDefaults = AppGroup.defaults
    ) {
        var all = entries(in: defaults).filter { now.timeIntervalSince($0.value.at) < lifetime }
        all[entryKey(statusID, accountID)] = Entry(favourited: favourited, at: now)
        save(all, in: defaults)
    }

    /// Takes a tap back: the server refused it, so the cache is right again.
    public static func clear(
        statusID: String, accountID: UUID, in defaults: UserDefaults = AppGroup.defaults
    ) {
        var all = entries(in: defaults)
        guard all.removeValue(forKey: entryKey(statusID, accountID)) != nil else { return }
        save(all, in: defaults)
    }

    private static func entryKey(_ statusID: String, _ accountID: UUID) -> String {
        "\(accountID.uuidString)/\(statusID)"
    }

    private static func entries(in defaults: UserDefaults) -> [String: Entry] {
        guard let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func save(_ entries: [String: Entry], in defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}
