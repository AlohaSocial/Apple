// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaStore
import Foundation
import OSLog
import UserNotifications

/// Raises the app's own notifications from what polling found, because the
/// server cannot push (docs/08 §5).
public struct LocalNotifier: Sendable {
    /// `UNUserNotificationCenter` is a non-`Sendable` singleton that is safe to
    /// reach from anywhere, so it is fetched per call rather than stored.
    private var center: UNUserNotificationCenter { .current() }
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "notifications")

    public init() {}

    public func requestAuthorisation() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    public func registerCategories() {
        let reply = UNTextInputNotificationAction(
            identifier: "reply", title: String(localized: "Reply", comment: "Notification action"),
            options: [],
            textInputButtonTitle: String(localized: "Send", comment: "Notification action"),
            textInputPlaceholder: "")
        let favourite = UNNotificationAction(
            identifier: "favourite",
            title: String(localized: "Favourite", comment: "Notification action"), options: [])
        let boost = UNNotificationAction(
            identifier: "boost",
            title: String(localized: "Boost", comment: "Notification action"), options: [])

        let mention = UNNotificationCategory(
            identifier: "mention", actions: [reply, favourite, boost],
            intentIdentifiers: [], options: [])
        let generic = UNNotificationCategory(
            identifier: "generic", actions: [], intentIdentifiers: [], options: [])

        center.setNotificationCategories([mention, generic])
    }

    /// Returns the ids that were actually announced, so the caller can mark
    /// exactly those and no others.
    @discardableResult
    public func announce(
        _ notifications: [StoredNotification],
        session: AccountSession,
        isQuiet: Bool,
        showAccountName: Bool
    ) async -> [String] {
        let enabled = session.settings.localNotificationKinds
        let eligible = notifications.filter { enabled.contains($0.kind.rawValue) }
        let authorization = await center.notificationSettings().authorizationStatus
        guard authorization == .authorized || authorization == .provisional else {
            // Do not retry the same historical rows on every poll or flood the
            // person if they enable notifications later.
            return eligible.map(\.serverID)
        }
        var announced: [String] = []

        for notification in eligible {
            // During quiet hours the badge still updates; only the alert is
            // withheld, and the row is marked so it is not re-raised later.
            guard !isQuiet else {
                announced.append(notification.serverID)
                continue
            }

            let content = UNMutableNotificationContent()
            let payload = NotificationPayload.decode(notification.payload)

            content.title = title(for: notification, payload: payload)
            content.body = payload?.body ?? ""
            if showAccountName { content.subtitle = session.snapshot.qualifiedHandle }
            content.categoryIdentifier = notification.kind == .mention ? "mention" : "generic"
            // A mention or a DM is worth interrupting for; a favourite is not.
            content.interruptionLevel = notification.kind == .mention ? .active : .passive
            content.threadIdentifier = payload?.statusID ?? notification.serverID
            content.userInfo = [
                "accountID": session.id.uuidString,
                "statusID": payload?.statusID ?? "",
                "notificationID": notification.serverID,
            ]
            if notification.kind != .follow {
                content.sound = nil
            }

            // The same request identifier per group, so a group that grows
            // replaces its notification rather than adding another.
            let request = UNNotificationRequest(
                identifier: "\(session.id.uuidString)-\(notification.serverID)",
                content: content, trigger: nil)

            do {
                try await center.add(request)
                announced.append(notification.serverID)
            } catch {
                logger.error(
                    "could not raise a notification: \(String(describing: error), privacy: .public)"
                )
            }
        }
        return announced
    }

    private func title(
        for notification: StoredNotification, payload: NotificationPayload?
    ) -> String {
        let who = payload?.title ?? String(localized: "Someone", comment: "Unknown account")
        let others = max(0, notification.groupCount - 1)
        let subject =
            others == 0
            ? who
            : String(localized: "\(who) and \(others) others", comment: "Grouped notification")

        switch notification.kind {
        case .mention:
            return String(localized: "\(subject) mentioned you", comment: "Notification title")
        case .favourite:
            return String(
                localized: "\(subject) favourited your post", comment: "Notification title")
        case .reblog:
            return String(localized: "\(subject) boosted your post", comment: "Notification title")
        case .follow:
            return String(localized: "\(subject) followed you", comment: "Notification title")
        case .followRequest:
            return String(
                localized: "\(subject) asked to follow you", comment: "Notification title")
        case .poll: return String(localized: "A poll has ended", comment: "Notification title")
        case .update:
            return String(localized: "\(subject) edited a post", comment: "Notification title")
        case .status: return String(localized: "\(subject) posted", comment: "Notification title")
        case .moderationWarning:
            return String(
                localized: "A moderator acted on your account", comment: "Notification title")
        case .severedRelationships:
            return String(localized: "Some of your follows were cut", comment: "Notification title")
        default: return subject
        }
    }

    public func setBadge(_ count: Int) async {
        try? await center.setBadgeCount(count)
    }

    public func clearAll() {
        center.removeAllDeliveredNotifications()
    }
}
