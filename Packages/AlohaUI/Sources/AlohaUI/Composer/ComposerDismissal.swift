// SPDX-License-Identifier: MIT

import Foundation

/// When the composer may be swiped away, and when it may not.
///
/// A swipe down on a sheet is the easiest gesture there is, and it used to be
/// the one way out that saved nothing: only Cancel wrote the draft. So a
/// composer holding anything worth keeping does not go on a swipe at all —
/// Cancel, which saves, is the way out — and one holding nothing does, the
/// way an empty Mail draft does.
struct ComposerDismissal: Equatable {
    var text: String
    var spoilerText: String
    var hasAttachments: Bool
    var hasPoll: Bool
    var threadSegments: [String]
    /// The original text of a post being edited; nil for a new post.
    var editBaseline: String?

    /// Whether closing now would lose something the person wrote.
    var isGuarded: Bool {
        if let editBaseline {
            // An edit is not a draft and is never saved as one, so any change
            // at all is work a swipe would throw away.
            return text != editBaseline
        }
        return !Self.isBlank(text) || !Self.isBlank(spoilerText) || hasAttachments || hasPoll
            || threadSegments.contains { !Self.isBlank($0) }
    }

    private static func isBlank(_ string: String) -> Bool {
        string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
