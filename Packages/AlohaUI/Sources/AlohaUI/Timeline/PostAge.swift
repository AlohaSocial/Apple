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

    static func isRecent(_ date: Date, now: Date) -> Bool {
        now.timeIntervalSince(date) < recentThreshold
    }
}
