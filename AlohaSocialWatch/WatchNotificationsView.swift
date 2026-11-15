// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The notifications list, with what groups collapsed to one summary row:
/// "Alice and 3 others favourited your post" is one thing to read on a
/// wrist, not four (docs/09 §4).
struct WatchNotificationsView: View {
    @Environment(WatchLink.self) private var link
    @State private var feed = WatchFeed<MastodonNotification>(.notifications)

    var body: some View {
        List {
            ForEach(WatchNotificationGroup.collapse(feed.items)) { group in
                if let status = group.status {
                    NavigationLink {
                        WatchStatusView(status: status)
                    } label: {
                        WatchNotificationRow(group: group)
                    }
                } else {
                    WatchNotificationRow(group: group)
                }
            }
            if feed.items.isEmpty && !feed.isLoading && !feed.isShowingCache {
                Text("No notifications yet", comment: "Watch, empty notifications list")
                    .font(.caption2)
            }
            if feed.isShowingCache {
                WatchUpdatedHint(updatedAt: feed.updatedAt)
            }
        }
        .navigationTitle(Text("Notifications", comment: "Watch notifications screen title"))
        .task(id: link.credentials?.accountID) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        await feed.load(accountID: link.credentials?.accountID) {
            guard let client = link.client else { throw APIError.invalidResponse }
            // Every kind named, as the complication's count names them:
            // Aloha Social sends its own kinds only when asked, and Mastodon
            // ignores the ones it does not know.
            return try await client.decode(
                LossyArray<MastodonNotification>.self,
                from: Endpoint.notifications.flat(
                    limit: 30, types: Endpoint.notifications.everyType(onAlohaSocial: true))
            ).elements
        }
    }
}

/// Notifications of a kind that groups — favourites, boosts, follows — about
/// the same post, folded into one row in the place of the newest.
struct WatchNotificationGroup: Identifiable {
    var id: String
    var kind: NotificationKind
    var accounts: [Account]
    var status: Status?

    static func collapse(_ notifications: [MastodonNotification]) -> [WatchNotificationGroup] {
        var groups: [WatchNotificationGroup] = []
        var indexByKey: [String: Int] = [:]
        for notification in notifications {
            guard notification.type.groups else {
                groups.append(
                    WatchNotificationGroup(
                        id: notification.id, kind: notification.type,
                        accounts: [notification.account], status: notification.status))
                continue
            }
            let key = "\(notification.type.rawValue)|\(notification.status?.id ?? "")"
            if let index = indexByKey[key] {
                if !groups[index].accounts.contains(where: { $0.id == notification.account.id }) {
                    groups[index].accounts.append(notification.account)
                }
            } else {
                indexByKey[key] = groups.count
                groups.append(
                    WatchNotificationGroup(
                        id: notification.id, kind: notification.type,
                        accounts: [notification.account], status: notification.status))
            }
        }
        return groups
    }

    var symbol: String {
        switch kind {
        case .mention: "at"
        case .favourite, .blueskyRepostLiked: AlohaSymbol.favouriteFilled
        case .reblog, .blueskyRepostReposted: AlohaSymbol.boost
        case .follow: "person.badge.plus"
        case .followRequest: "person.badge.clock"
        case .poll: AlohaSymbol.poll
        case .update: AlohaSymbol.edit
        case .status: AlohaSymbol.reply
        default: AlohaSymbol.notifications
        }
    }

    /// The phone's own sentences, shortened to what fits a wrist.
    var summary: String {
        let name =
            accounts.first?.bestDisplayName
            ?? String(localized: "Someone", comment: "Watch, unknown account in a notification")
        let others = accounts.count - 1
        let who =
            others <= 0
            ? name
            : String(
                localized: "\(name) and \(others) others",
                comment: "Watch, grouped notification participants")
        switch kind {
        case .mention:
            return String(localized: "\(who) mentioned you", comment: "Watch notification summary")
        case .favourite:
            return String(
                localized: "\(who) favourited your post", comment: "Watch notification summary")
        case .reblog:
            return String(
                localized: "\(who) boosted your post", comment: "Watch notification summary")
        case .follow:
            return String(localized: "\(who) followed you", comment: "Watch notification summary")
        case .followRequest:
            return String(
                localized: "\(who) asked to follow you", comment: "Watch notification summary")
        case .poll:
            return String(localized: "A poll has ended", comment: "Watch notification summary")
        case .update:
            return String(localized: "\(who) edited a post", comment: "Watch notification summary")
        case .status:
            return String(localized: "\(who) posted", comment: "Watch notification summary")
        case .storyReaction:
            return String(
                localized: "\(who) reacted to your story", comment: "Watch notification summary")
        case .storyComment:
            return String(
                localized: "\(who) replied to your story", comment: "Watch notification summary")
        case .tagged:
            return String(
                localized: "\(who) tagged you in a photo", comment: "Watch notification summary")
        default:
            return who
        }
    }
}

struct WatchNotificationRow: View {
    let group: WatchNotificationGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(verbatim: group.summary)
                    .lineLimit(2)
            } icon: {
                Image(systemName: group.symbol)
                    .foregroundStyle(.tint)
            }
            .font(.caption2.weight(.semibold))

            if let status = group.status {
                // The post it is about, by the same rules as any row: its
                // warning before its words.
                let warning = WatchText.warning(of: status)
                if warning.isEmpty {
                    Text(WatchText.body(of: status))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    WatchWarningLabel(warning: warning)
                        .lineLimit(2)
                }
            }
        }
    }
}
