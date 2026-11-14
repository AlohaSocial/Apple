// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import Foundation

/// How an alert about one notification is labelled, whoever raises it.
///
/// The app raises its own from what polling finds (`LocalNotifier`) and the
/// notification service extension rewrites what Nextcloud's push proxy
/// delivers. Both used to decide these on their own, and the push got none of
/// them: no actions, no grouping, no post to open, no Focus filter. Here once,
/// so a mention behaves the same however it arrived.
///
/// Values only, no `UserNotifications`, so the store stays buildable for the
/// platforms that have no notification categories (tvOS).
public enum NotificationAlert {
    /// The category whose actions — Reply, Favourite, Boost, Mute
    /// conversation — `LocalNotifier.registerCategories` registers.
    public static let mentionCategory = "mention"
    /// Everything else: a tap opens it, and there are no actions.
    public static let genericCategory = "generic"

    /// `userInfo` keys `NotificationReply` reads back when the person acts.
    public static let accountIDKey = "accountID"
    public static let statusIDKey = "statusID"
    public static let notificationIDKey = "notificationID"
    /// The Nextcloud notification a push came from, which a later withdrawal
    /// names.
    public static let nextcloudNotificationIDKey = "nextcloudNotificationID"

    /// A reply is a mention: Mastodon's own API has no separate "reply" kind,
    /// and the mention category carries the actions people want on both.
    public static func category(for kind: NotificationKind?) -> String {
        kind == .mention ? mentionCategory : genericCategory
    }

    /// Somebody talking to you interrupts; favourites, boosts and follows
    /// arrive quietly.
    public static func isActive(_ kind: NotificationKind?) -> Bool {
        kind == .mention
    }

    /// Replies to one post group together in Notification Centre; a
    /// notification about no post is a thread of its own.
    public static func threadIdentifier(statusID: String?, notificationID: String) -> String {
        statusID.flatMap { $0.isEmpty ? nil : $0 } ?? notificationID
    }

    /// What the alert carries for a tap or an action to act on. The account
    /// is also the alert's `filterCriteria`, which a Focus set to one account
    /// matches (`AlohaFocusFilter.appContext`).
    public static func userInfo(
        accountID: UUID, statusID: String?, notificationID: String
    ) -> [String: String] {
        [
            accountIDKey: accountID.uuidString,
            statusIDKey: statusID ?? "",
            notificationIDKey: notificationID,
        ]
    }

    // MARK: - Announced by push

    /// How many ids are remembered per account: far more than one poll can
    /// find, few enough that the defaults stay small.
    static let pushAnnouncedLimit = 100

    /// Records that a push already announced this notification, so the poll
    /// that finds it later does not raise it again.
    ///
    /// Both forms of its id are kept: a v1 id is what the push extension
    /// looks up, and a v2 group of one is `ungrouped-<id>`, which is what a
    /// poll of the grouped API stores. A notification the server groups with
    /// others (favourites of one post) has a group key that cannot be worked
    /// out from here, and may still be announced twice.
    public static func notePushAnnounced(
        _ notificationID: String, accountID: UUID, in defaults: UserDefaults = AppGroup.defaults
    ) {
        var all =
            defaults.dictionary(forKey: AppGroup.pushAnnouncedKey) as? [String: [String]] ?? [:]
        var ids = all[accountID.uuidString] ?? []
        ids.append(contentsOf: [notificationID, "ungrouped-\(notificationID)"])
        all[accountID.uuidString] = Array(ids.suffix(pushAnnouncedLimit))
        defaults.set(all, forKey: AppGroup.pushAnnouncedKey)
    }

    /// The ids a push already announced for one account.
    public static func pushAnnounced(
        accountID: UUID, in defaults: UserDefaults = AppGroup.defaults
    ) -> Set<String> {
        let all = defaults.dictionary(forKey: AppGroup.pushAnnouncedKey) as? [String: [String]]
        return Set(all?[accountID.uuidString] ?? [])
    }
}
