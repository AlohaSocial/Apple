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
        // "Mute conversation" on mention/reply notifications (Issue #3).
        let muteConversation = UNNotificationAction(
            identifier: "muteConversation",
            title: String(localized: "Mute conversation", comment: "Notification action"),
            options: [.destructive])

        // One category, because a reply is a mention: Mastodon's API has no
        // "reply" kind, so every notification that can be replied to arrives
        // as a mention and wears this category's actions.
        let mention = UNNotificationCategory(
            identifier: "mention", actions: [reply, favourite, boost, muteConversation],
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
            return eligible.map(\.serverID)
        }
        var announced: [String] = []

        let deliveryMode = session.settings.notificationDeliveryMode
        let digestTimes = session.settings.digestTimes.isEmpty ? [8] : session.settings.digestTimes
        let quietStart = session.settings.quietHoursStart
        let quietEnd = session.settings.quietHoursEnd

        let announcements = isQuiet ? [] : eligible

        if deliveryMode == .digest {
            // A mention is the thing somebody wants answered, so it always
            // comes through immediately even in digest mode. Everything else
            // waits for the next digest time and is posted there as ONE
            // summary, grouped by kind — not as seventeen separate
            // notifications at the same minute (docs/08 §8).
            let breaking = announcements.filter { $0.kind == NotificationKind.mention }
            for notification in breaking {
                let content = content(
                    for: notification, session: session, showAccountName: showAccountName)
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
            let held = announcements.filter { $0.kind != NotificationKind.mention }
            do {
                try await postDigestSummary(
                    held, session: session, times: digestTimes, quietStart: quietStart,
                    quietEnd: quietEnd)
            } catch {
                // A summary that could not be scheduled is not a reason to
                // drop the notifications: UNUserNotificationCenter keeps the
                // running summary, and the next poll will try again. The rows
                // are still marked announced so they are not re-announced.
                logger.error(
                    "could not post a digest summary: \(String(describing: error), privacy: .public)"
                )
            }
            announced.append(contentsOf: held.map { $0.serverID })
            return announced
        }

        for notification in announcements {
            let content = content(
                for: notification, session: session, showAccountName: showAccountName)
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

    /// One request for everything held since the last digest.
    ///
    /// The id is the digest *time*, not a notification: a later poll replaces
    /// the pending summary rather than stacking a second one, which means a
    /// person who receives four things through the day gets one notification
    /// at 08:00 that says what they were, not four.
    ///
    /// The running totals live in the request's own `userInfo`: a replace
    /// needs to know what the previous summary said, or the count would go
    /// back down each time.
    private func postDigestSummary(
        _ held: [StoredNotification],
        session: AccountSession,
        times: [Int],
        quietStart: Int?,
        quietEnd: Int?
    ) async throws {
        guard !held.isEmpty else { return }
        guard
            let trigger = nextDigestTrigger(
                times: times, quietStart: quietStart, quietEnd: quietEnd),
            let calendarTrigger = trigger as? UNCalendarNotificationTrigger,
            let nextDate = calendarTrigger.nextTriggerDate()
        else { return }

        // One identity per digest time, so successive polls replace.
        let digestID = "\(session.id.uuidString)-digest-\(Int(nextDate.timeIntervalSince1970))"

        // Whatever is already pending for this digest, plus what arrived now.
        let pendingCounts = await pendingDigestCounts(withIDs: [digestID])
        var totals = pendingCounts.first ?? [:]
        for notification in held {
            totals[notification.kind.rawValue, default: 0] += 1
        }

        let content = UNMutableNotificationContent()
        let total = totals.values.reduce(0, +)
        content.title =
            total == 1
            ? String(localized: "1 notification", comment: "Digest summary title")
            : String(
                localized: "\(total) notifications",
                comment: "Digest summary title")
        content.body =
            totals
            .sorted { $0.key < $1.key }
            .compactMap { NotificationKind(rawValue: $0.key) }
            .map { kind in
                let label = kindName(kind)
                return "\(totals[kind.rawValue] ?? 0) \(label)"
            }
            .joined(separator: " · ")
        // A summary is not a conversation, so it does not need a sound and
        // does not interrupt: it is the day's mail, not a message.
        content.sound = nil
        content.interruptionLevel = .passive
        content.userInfo = [
            "accountID": session.id.uuidString,
            "digestCounts": totals,
        ]

        let request = UNNotificationRequest(
            identifier: digestID, content: content, trigger: trigger)
        try await center.add(request)
    }

    /// The pending summaries this app has already scheduled for the given ids.
    ///
    /// `UNNotificationRequest` is not Sendable, so the counts are read inside
    /// the centre's callback and only `[String: Int]` crosses the boundary.
    private func pendingDigestCounts(withIDs: [String]) async -> [[String: Int]] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                let counts =
                    requests
                    .filter { withIDs.contains($0.identifier) }
                    .compactMap {
                        $0.content.userInfo["digestCounts"] as? [String: Int]
                    }
                continuation.resume(returning: counts)
            }
        }
    }

    /// A notification kind as it reads in a summary line: "5 favourites".
    private func kindName(_ kind: NotificationKind) -> String {
        switch kind {
        case .mention: String(localized: "mention", comment: "Digest summary kind")
        case .reblog: String(localized: "boost", comment: "Digest summary kind")
        case .favourite: String(localized: "favourite", comment: "Digest summary kind")
        case .follow: String(localized: "follow", comment: "Digest summary kind")
        case .followRequest: String(localized: "request", comment: "Digest summary kind")
        case .poll: String(localized: "poll", comment: "Digest summary kind")
        case .status: String(localized: "reply", comment: "Digest summary kind")
        case .update: String(localized: "update", comment: "Digest summary kind")
        case .adminSignUp: String(localized: "sign-up", comment: "Digest summary kind")
        case .adminReport: String(localized: "report", comment: "Digest summary kind")
        case .moderationWarning: String(localized: "warning", comment: "Digest summary kind")
        case .severedRelationships: String(localized: "separation", comment: "Digest summary kind")
        case .annualReport: String(localized: "report", comment: "Digest summary kind")
        default:
            // Everything this app has no name for — the kinds a newer server
            // can add — reads as the server's own raw value rather than being
            // dropped by a switch that must be exhaustive.
            kind.rawValue
        }
    }

    /// The content for one notification, as it is announced on its own.
    private func content(
        for notification: StoredNotification, session: AccountSession,
        showAccountName: Bool
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let payload = NotificationPayload.decode(notification.payload)

        content.title = title(for: notification, payload: payload)
        content.body = payload?.body ?? ""
        if showAccountName { content.subtitle = session.snapshot.qualifiedHandle }
        // A reply is a mention: Mastodon's own API has no separate
        // "reply" kind, and the mention category carries the actions
        // people want on both.
        content.categoryIdentifier =
            notification.kind == NotificationKind.mention ? "mention" : "generic"
        content.interruptionLevel =
            notification.kind == NotificationKind.mention ? .active : .passive
        content.threadIdentifier = payload?.statusID ?? notification.serverID
        content.userInfo = [
            "accountID": session.id.uuidString,
            "statusID": payload?.statusID ?? "",
            "notificationID": notification.serverID,
        ]
        if notification.kind != .follow {
            content.sound = nil
        }
        return content
    }

    /// Returns the next digest trigger after now, skipping quiet hours.
    /// If all digest times are in the past today, the first one tomorrow is used.
    private func nextDigestTrigger(
        times: [Int], quietStart: Int?, quietEnd: Int?
    ) -> UNCalendarNotificationTrigger? {
        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)

        guard
            let h = Self.nextDigestHour(
                times: times, quietStart: quietStart, quietEnd: quietEnd,
                hour: hour, minute: minute)
        else { return nil }  // every digest time falls inside quiet hours

        // Build the date for the target hour, today when the hour has not
        // passed and tomorrow when it has.
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        if h < hour || (h == hour && minute > 0) {
            comps.day = (comps.day ?? 1) + 1
        }
        comps.hour = h
        comps.minute = 0
        guard let date = cal.date(from: comps) else { return nil }
        return UNCalendarNotificationTrigger(
            dateMatching: cal.dateComponents([.hour, .minute, .day, .month, .year], from: date),
            repeats: false)
    }

    /// The hour of the next digest, as a pure function of the clock.
    ///
    /// The rule, in the order it decides: the first picked hour still ahead of
    /// now — the same hour counts only while the minute is exactly zero —
    /// otherwise the earliest picked hour, treated as tomorrow. An hour inside
    /// quiet hours is skipped forward, and when every picked hour is quiet the
    /// answer is nil, because quiet hours win over a digest time (docs/08 §8).
    ///
    /// Static and pure, so the rule is testable without a clock or a
    /// notification centre.
    static func nextDigestHour(
        times: [Int], quietStart: Int?, quietEnd: Int?, hour: Int, minute: Int
    ) -> Int? {
        let sorted = times.sorted()
        guard !sorted.isEmpty else { return nil }

        func inQuietHours(_ h: Int) -> Bool {
            guard let start = quietStart, let end = quietEnd else { return false }
            return start > end
                ? h >= start || h < end  // wraps midnight
                : h >= start && h < end
        }

        var h = sorted.first { $0 > hour || ($0 == hour && minute == 0) } ?? sorted[0]

        // Quiet hours can only skip *forward*, so the candidate list is walked
        // in order; the wrap is bounded so a pathological list cannot loop.
        var checked = 0
        while inQuietHours(h), checked < times.count {
            if let idx = sorted.firstIndex(of: h) {
                h = sorted[(idx + 1) % sorted.count]
            }
            checked += 1
        }

        return inQuietHours(h) ? nil : h
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
