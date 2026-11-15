// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation

/// How Activities pages back through time and what it asks the server for.
///
/// The list used to load one page and filter it on the device, so the
/// Mentions chip showed the mentions among the last forty activities and an
/// older one could not be reached at all. Both routes take `max_id` and
/// `types[]` (docs/08 §8), so the chips ask the server and the list pages
/// back from its oldest row.
nonisolated enum ActivityPaging {
    /// Grouped pages: Mastodon caps a grouped page at forty notifications.
    static let groupedLimit = 40
    /// Flat pages: the route's own default.
    static let flatLimit = Endpoint.defaultLimit

    /// What to send as `types[]` for the chips chosen.
    ///
    /// None chosen is the whole list, which on Aloha Social has to name every
    /// type the app draws (`everyType`). A chosen chip names its own types,
    /// and Follows includes follow requests, as the chip always has. Naming
    /// types is an allow-list on every server, so this narrows the same way
    /// everywhere.
    static func types(for selected: Set<NotificationKind>, onAlohaSocial: Bool) -> [String] {
        guard !selected.isEmpty else {
            return Endpoint.notifications.everyType(onAlohaSocial: onAlohaSocial)
        }
        var kinds = selected
        if kinds.contains(.follow) { kinds.insert(.followRequest) }
        return kinds.map(\.rawValue).sorted()
    }

    /// The `max_id` for the page older than these groups: the oldest
    /// notification any of them shows on the pages loaded so far.
    static func olderAnchor(groups: [NotificationGroup]) -> String? {
        oldest(groups.map { $0.pageMinID ?? $0.mostRecentNotificationID })
    }

    /// The `max_id` for the page older than these notifications.
    static func olderAnchor(flat: [MastodonNotification]) -> String? {
        oldest(flat.map(\.id))
    }

    private static func oldest(_ ids: [String]) -> String? {
        ids.filter { !$0.isEmpty }.min { SupportStore.isNewer($1, than: $0) }
    }

    /// An older page added under the groups already shown.
    ///
    /// A group can span pages: its newer notifications on one, its older on
    /// the next. It stays where it first appeared — that is where its newest
    /// activity puts it — and only learns how far back it now reaches, so
    /// the next page is asked from the right place. `notifications_count`
    /// is already the group's total, so it is not added up.
    static func appending(
        _ older: [NotificationGroup], to existing: [NotificationGroup]
    ) -> [NotificationGroup] {
        var merged = existing
        var position: [String: Int] = [:]
        for (index, group) in merged.enumerated() { position[group.groupKey] = index }
        for group in older {
            if let index = position[group.groupKey] {
                if let olderMin = group.pageMinID {
                    merged[index].pageMinID = olderMin
                }
            } else {
                position[group.groupKey] = merged.count
                merged.append(group)
            }
        }
        return merged
    }

    /// An older flat page added under the notifications already shown,
    /// leaving out any the server sent twice.
    static func appending(
        _ older: [MastodonNotification], to existing: [MastodonNotification]
    ) -> [MastodonNotification] {
        var seen = Set(existing.map(\.id))
        return existing + older.filter { seen.insert($0.id).inserted }
    }

    /// Whether to ask for another page after one came back.
    ///
    /// A `Link` header is trusted where the server sends one. Without it, an
    /// empty page is the end — and so is a page that moved nothing, which is
    /// what a server that ignores `max_id` answers: the same page again,
    /// forever, if nothing stopped it.
    static func mayHaveMore(
        link: LinkHeader, receivedAny: Bool, previousAnchor: String?, nextAnchor: String?
    ) -> Bool {
        if !link.isEmpty { return link.next != nil && nextAnchor != previousAnchor }
        return receivedAny && nextAnchor != nil && nextAnchor != previousAnchor
    }
}
