// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// What a poll may be on this server, from its own configuration
/// (`configuration.polls`, docs/07 §5) — never hardcoded (docs/02 §3).
///
/// The composer used to send every poll for 24 hours with its totals shown,
/// and let a choice run past `max_characters_per_option` for the server to
/// refuse the whole post.
nonisolated enum PollRules {
    /// The durations offered, before the server's bounds narrow them: five
    /// minutes to seven days, the steps every Mastodon client offers.
    static let standardDurations: [Int] = [
        5 * 60, 30 * 60, 60 * 60, 6 * 3_600, 12 * 3_600, 86_400, 3 * 86_400, 7 * 86_400,
    ]
    /// A day, as the composer has always sent.
    static let defaultDuration = 86_400

    /// The standard durations the server accepts. A server whose bounds
    /// leave none of them (an odd `min_expiration`) is offered its own
    /// bounds instead, so there is always something to choose.
    static func durations(within limits: ServerLimits) -> [Int] {
        let low = Int(limits.minPollExpiration)
        let high = Int(limits.maxPollExpiration)
        guard low <= high, high > 0 else { return standardDurations }
        let allowed = standardDurations.filter { $0 >= low && $0 <= high }
        if !allowed.isEmpty { return allowed }
        return low == high ? [low] : [low, high]
    }

    /// The offered duration closest to `seconds`: a draft from another
    /// server, or the default on a server that caps polls at an hour, still
    /// lands on something this one accepts.
    static func closestDuration(to seconds: Int, within limits: ServerLimits) -> Int {
        let offered = durations(within: limits)
        return offered.min { abs($0 - seconds) < abs($1 - seconds) } ?? seconds
    }

    /// Characters left in one choice; below zero, it is too long.
    static func remaining(in option: String, limits: ServerLimits) -> Int {
        limits.maxPollOptionCharacters - option.count
    }

    /// Why this poll cannot be posted as it stands, or nil when it can.
    ///
    /// Empty choices are dropped when posting, and a poll left with none is
    /// no poll at all — the composer has always worked that way, so opening
    /// the editor and closing it untouched does not block the post.
    static func problem(options: [String], limits: ServerLimits) -> Problem? {
        let filled = options.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if filled.isEmpty { return nil }
        if filled.count < 2 { return .tooFewChoices }
        if filled.count > limits.maxPollOptions { return .tooManyChoices(limits.maxPollOptions) }
        if filled.contains(where: { remaining(in: $0, limits: limits) < 0 }) {
            return .choiceTooLong(limits.maxPollOptionCharacters)
        }
        return nil
    }

    enum Problem: Equatable, Sendable {
        case tooFewChoices
        case tooManyChoices(Int)
        case choiceTooLong(Int)

        var message: String {
            switch self {
            case .tooFewChoices:
                String(
                    localized: "A poll needs at least two choices.",
                    comment: "Composer poll problem")
            case .tooManyChoices(let maximum):
                String(
                    localized: "This server allows at most \(maximum) choices.",
                    comment: "Composer poll problem. The argument is a number.")
            case .choiceTooLong(let maximum):
                String(
                    localized: "Each choice can be at most \(maximum) characters.",
                    comment: "Composer poll problem. The argument is a number.")
            }
        }
    }

    /// "5 minutes", "6 hours", "3 days": how a duration is offered.
    static func label(for seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds % 86_400 == 0 ? [.day] : [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: TimeInterval(seconds)) ?? "\(seconds)"
    }
}
