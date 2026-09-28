// SPDX-License-Identifier: MIT

import Foundation

/// Mastodon's character counting, done in one place.
///
/// The subtlety that makes this worth a type: a URL costs a **fixed** number of
/// characters however long it is, and the content warning counts against the
/// same budget as the body. The trap is units — `NSRegularExpression` works in
/// UTF-16 offsets while a person counts grapheme clusters, so mixing the two
/// makes the counter wrong for any post containing an emoji.
public enum CharacterCount {
    /// Matches what the server's own linkifier treats as a URL.
    static let urlPattern = #"https?://[^\s<]+"#

    public static func count(text: String, spoilerText: String, limits: ServerLimits) -> Int {
        weighted(text, limits: limits) + spoilerText.count
    }

    public static func remaining(
        text: String, spoilerText: String, limits: ServerLimits
    ) -> Int {
        limits.maxStatusCharacters - count(text: text, spoilerText: spoilerText, limits: limits)
    }

    /// The body's cost, with each URL charged the flat rate.
    static func weighted(_ text: String, limits: ServerLimits) -> Int {
        guard let regex = try? NSRegularExpression(pattern: urlPattern) else {
            return text.count
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return text.count }

        // Convert each match back into a `String` range before counting, so
        // everything below is in grapheme clusters and nothing is in UTF-16.
        var urlCharacters = 0
        for match in matches {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            urlCharacters += text[swiftRange].count
        }

        return text.count - urlCharacters + matches.count * limits.charactersReservedPerURL
    }
}
