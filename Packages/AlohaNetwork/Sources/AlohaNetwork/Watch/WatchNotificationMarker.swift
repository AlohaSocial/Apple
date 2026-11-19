// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// Reading the notifications on the watch counts as reading them.
///
/// The watch used to show the list and leave the server's notifications
/// marker where it was, so the count on the face, the phone's badge and
/// the phone's own list all went on saying "unread" about things already
/// read on the wrist. Writing the marker is what every other client does
/// when its list is seen, and it is what `unread_count` counts from.
public enum WatchNotificationMarker {
    /// Snowflake order: a longer id is newer, equal lengths compare as text
    /// — the phone's rule (`SupportStore.isNewer`), which this package
    /// cannot import.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        if candidate.count != current.count { return candidate.count > current.count }
        return candidate > current
    }

    /// The newest of `ids`, where it is newer than `current`; nil where there
    /// is nothing to move the marker to.
    public static func target(newestOf ids: [String], current: String?) -> String? {
        guard let newest = ids.max(by: { isNewer($1, than: $0) }) else { return nil }
        if let current, !isNewer(newest, than: current) { return nil }
        return newest
    }

    /// Moves the notifications marker up to the newest of `ids`, and returns
    /// the id written, or nil where it was already there or beyond.
    ///
    /// The marker is read first. Mastodon does not refuse a marker that moves
    /// backwards, and a watch whose list is a few minutes old must not un-read
    /// what the phone has read since (docs/08 §7).
    @discardableResult
    public static func markRead(_ ids: [String], client: APIClient) async throws -> String? {
        guard !ids.isEmpty else { return nil }
        let current = try await client.decode(MarkerSet.self, from: Endpoint.markers.read)
        guard let target = target(newestOf: ids, current: current.notifications?.lastReadID)
        else { return nil }
        _ = try await client.send(Endpoint.markers.write(home: nil, notifications: target))
        return target
    }
}
