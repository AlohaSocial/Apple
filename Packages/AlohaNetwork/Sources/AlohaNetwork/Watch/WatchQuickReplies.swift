// SPDX-License-Identifier: MIT

import Foundation

/// The canned answers the watch offers above its reply field (docs/09 §4).
///
/// A wrist answers in a word more often than in a sentence, and dictation in
/// a quiet room or a loud street is the wrong tool for "Thanks!". The phone
/// keeps the list — it has a keyboard to edit it with — and sends it in the
/// WatchConnectivity application context beside the pairing; the watch keeps
/// the last list it received, and falls back to a built-in set where the
/// phone never sent one.
public enum WatchQuickReplies {
    /// The application-context key the list travels under, beside
    /// `WatchPairing.contextKey`. Absent means "the built-in set", so a phone
    /// that never edited the list, or an older build, sends nothing.
    public static let contextKey = "quickReplies"

    /// Where each side keeps its copy. Absent, as in the context, means the
    /// built-in set; an empty array is a person who removed them all.
    public static let defaultsKey = "aloha.watchQuickReplies"

    /// The most the watch shows: a ninth button is a scroll too far on a
    /// wrist (docs/09 §4).
    public static let limit = 8

    /// A chip is a phrase, not a post.
    public static let maxLength = 100

    /// Short, and safe to send to anyone: these go out as replies to public
    /// posts as often as to direct messages.
    public static var builtIn: [String] {
        [
            String(localized: "Thank you!", comment: "Watch quick reply"),
            String(localized: "Yes!", comment: "Watch quick reply"),
            String(localized: "No, sorry.", comment: "Watch quick reply"),
            String(localized: "Sounds good.", comment: "Watch quick reply"),
            String(localized: "Love this!", comment: "Watch quick reply"),
            String(localized: "I'll reply properly later.", comment: "Watch quick reply"),
        ]
    }

    /// The list as it may be shown and sent: trimmed, no blanks, no
    /// repeats (ignoring case), each phrase cut to `maxLength`, and no more
    /// than `limit` of them.
    public static func sanitized(_ phrases: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for phrase in phrases {
            let trimmed = String(
                phrase.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
            if result.count == limit { break }
        }
        return result
    }

    // MARK: - Storage

    /// The list a person chose, or nil where they never chose one.
    public static func stored(in defaults: UserDefaults = .standard) -> [String]? {
        (defaults.array(forKey: defaultsKey) as? [String]).map(sanitized)
    }

    /// What to offer: the chosen list, or the built-in set.
    public static func current(in defaults: UserDefaults = .standard) -> [String] {
        stored(in: defaults) ?? builtIn
    }

    /// Keeps `phrases`, or with nil goes back to the built-in set.
    public static func store(_ phrases: [String]?, in defaults: UserDefaults = .standard) {
        if let phrases {
            defaults.set(sanitized(phrases), forKey: defaultsKey)
        } else {
            defaults.removeObject(forKey: defaultsKey)
        }
    }

    // MARK: - The application context

    /// `phrases` added to a context the phone is about to send. Nil adds
    /// nothing, which the watch reads as "the built-in set".
    public static func adding(
        _ phrases: [String]?, to context: [String: Any]
    ) -> [String: Any] {
        guard let phrases else { return context }
        var copy = context
        copy[contextKey] = sanitized(phrases)
        return copy
    }

    /// The list in a received context, or nil where it carries none.
    public static func phrases(in context: [String: Any]) -> [String]? {
        (context[contextKey] as? [String]).map(sanitized)
    }
}
