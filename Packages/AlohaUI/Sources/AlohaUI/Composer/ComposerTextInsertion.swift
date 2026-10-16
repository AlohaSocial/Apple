// SPDX-License-Identifier: MIT

import Foundation

/// Putting a snippet — a custom emoji's `:shortcode:` — where the cursor is.
///
/// The composer appended everything at the end, so an emoji chosen in the
/// middle of a sentence landed after its last word. This puts it where the
/// person was typing, replacing any selected text the way a typed character
/// would, with a space either side only where one is missing.
enum ComposerTextInsertion {
    struct Result: Equatable {
        var text: String
        /// Where the cursor goes afterwards, as a character offset, so the
        /// caller can rebuild an index in the new string.
        var cursorOffset: Int
    }

    static func inserting(
        _ snippet: String, into text: String, replacing range: Range<String.Index>?
    ) -> Result {
        let range = range ?? text.endIndex..<text.endIndex
        let before = text[..<range.lowerBound]
        let after = text[range.upperBound...]

        let leading = before.last.map { $0.isWhitespace ? "" : " " } ?? ""
        let trailing = after.first.map { $0.isWhitespace ? "" : " " } ?? " "
        let inserted = leading + snippet + trailing

        return Result(
            text: String(before) + inserted + String(after),
            cursorOffset: before.count + inserted.count)
    }
}
