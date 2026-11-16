// SPDX-License-Identifier: MIT

import Foundation

/// A Live Activity counting down to something of the account's own: its
/// open poll closing, or its next scheduled post going out (docs/09 §9).
///
/// Here rather than in the app, because the widget extension draws it and
/// links this package but not the UI one. The countdown is drawn with
/// `Text(timerInterval:)`, which runs by itself on the Lock Screen and in the
/// Dynamic Island, so nothing ever has to push an update.
public struct EventActivityAttributes: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case pollCloses
        case scheduledPost
    }

    public var kind: Kind
    public var accountID: UUID
    /// The poll's post, or the scheduled post's id: what a tap opens.
    public var itemID: String
    /// When the countdown began, so the timer has a start to count from.
    public var startedAt: Date

    public init(kind: Kind, accountID: UUID, itemID: String, startedAt: Date) {
        self.kind = kind
        self.accountID = accountID
        self.itemID = itemID
        self.startedAt = startedAt
    }

    public struct ContentState: Sendable, Hashable, Codable {
        /// When the poll closes or the post goes out.
        public var at: Date
        /// The poll's question or the post's text, short; the content
        /// warning where the post has one, since a Lock Screen is public.
        public var text: String

        public init(at: Date, text: String) {
            self.at = at
            self.text = text
        }
    }
}

// ActivityKit exists on macOS as a module but `ActivityAttributes` does not,
// so the conformance is iOS-only rather than canImport-gated (as the upload's).
#if os(iOS)
    import ActivityKit

    extension EventActivityAttributes: ActivityAttributes {}
#endif

/// Which countdowns are due, from the snapshot the widgets already read.
public enum EventActivityPlanner {
    /// How far ahead an event earns a Live Activity. An hour is when a poll's
    /// last votes and a post's last edits happen; longer is a reminder, and
    /// reminders are not what Live Activities are for.
    public static let horizon: TimeInterval = 60 * 60
    /// The longest a Live Activity text runs before it is cut.
    static let textLimit = 80

    public struct Event: Sendable, Hashable {
        public var kind: EventActivityAttributes.Kind
        public var itemID: String
        public var at: Date
        public var text: String

        public init(kind: EventActivityAttributes.Kind, itemID: String, at: Date, text: String) {
            self.kind = kind
            self.itemID = itemID
            self.at = at
            self.text = text
        }
    }

    /// The account's open poll closing, and its next scheduled post going
    /// out, where either happens within the horizon. Nothing already past.
    public static func upcoming(in snapshot: WidgetSnapshot?, now: Date) -> [Event] {
        guard let snapshot else { return [] }
        var events: [Event] = []
        if let poll = snapshot.poll, !poll.isClosed(at: now), let closes = poll.expiresAt,
            isWithinHorizon(closes, now: now)
        {
            events.append(
                Event(
                    kind: .pollCloses, itemID: poll.statusID, at: closes,
                    text: shortened(poll.question)))
        }
        if let next = (snapshot.scheduled ?? []).filter({ $0.at > now }).min(by: { $0.at < $1.at }),
            isWithinHorizon(next.at, now: now)
        {
            events.append(
                Event(
                    kind: .scheduledPost, itemID: next.id, at: next.at,
                    text: shortened(next.text)))
        }
        return events
    }

    static func isWithinHorizon(_ date: Date, now: Date) -> Bool {
        date > now && date.timeIntervalSince(now) <= horizon
    }

    static func shortened(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count > textLimit ? String(flat.prefix(textLimit - 1)) + "…" : flat
    }
}
