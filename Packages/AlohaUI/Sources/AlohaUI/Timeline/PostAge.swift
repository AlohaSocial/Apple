// SPDX-License-Identifier: MIT

import Foundation

/// How old a post is, in words.
///
/// `Date.RelativeFormatStyle` alone says "in 0s" for a status posted a moment
/// ago — the server's clock, the network round trip and rounding together put
/// `createdAt` a fraction of a second into the future, and the app then claims
/// the post arrives from the future. Clock skew between a server and a phone
/// makes the same thing happen for minutes at a time.
///
/// So: anything not yet a minute old — including anything dated ahead of us —
/// reads "now", and only genuinely older posts get a relative time.
public enum PostAge {
    /// Under a minute is "now"; the rendering is not worth a unit of time.
    public static let recentThreshold: TimeInterval = 60

    /// The timeline's compact form: "now", "5m", "2d".
    public static func short(_ date: Date, now: Date = Date()) -> String {
        guard !isRecent(date, now: now) else {
            return String(localized: "now", comment: "Age of a post less than a minute old")
        }
        return date.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
    }

    /// The spoken form, for accessibility labels: "now", "5 minutes ago".
    public static func spoken(_ date: Date, now: Date = Date()) -> String {
        guard !isRecent(date, now: now) else {
            return String(localized: "now", comment: "Age of a post less than a minute old")
        }
        return date.formatted(.relative(presentation: .named))
    }

    /// The exact moment, for a tooltip and the focused post: "16 October
    /// 2026 at 14:05".
    public static func absolute(_ date: Date) -> String {
        date.formatted(date: .long, time: .shortened)
    }

    /// How long until `short` would read differently, so a live label redraws
    /// when its words change and not every second in between: each minute
    /// for the first hour, then each hour for the first day, then daily.
    public static func refreshInterval(for date: Date, now: Date = Date()) -> TimeInterval {
        let age = now.timeIntervalSince(date)
        if age < 3600 { return 60 }
        if age < 86_400 { return 3600 }
        return 86_400
    }

    static func isRecent(_ date: Date, now: Date) -> Bool {
        now.timeIntervalSince(date) < recentThreshold
    }
}
