// SPDX-License-Identifier: MIT

import Foundation

/// What the reader has chosen to see this session: posts whose content
/// warning they opened, and sensitive pictures they uncovered.
///
/// The rows keep their own disclosure state, as they always have; this is
/// the record of it that something *outside* a row can ask — the post card
/// shared as an image, which must never show what is behind a warning or a
/// cover unless the reader has looked behind it themselves. Memory only, and
/// only for the session, as the rows' own state is (docs/05 §3).
@MainActor
final class RevealedContent {
    static let shared = RevealedContent()

    /// Post ids, by the post actually shown — a boost's inner post.
    private(set) var spoilers: Set<String> = []
    /// Attachment ids.
    private(set) var media: Set<String> = []

    func setSpoiler(_ statusID: String, revealed: Bool) {
        if revealed { spoilers.insert(statusID) } else { spoilers.remove(statusID) }
    }

    func revealMedia(_ attachmentIDs: some Sequence<String>) {
        media.formUnion(attachmentIDs)
    }

    func isSpoilerRevealed(_ statusID: String) -> Bool { spoilers.contains(statusID) }

    func isMediaRevealed(_ attachmentIDs: some Sequence<String>) -> Bool {
        attachmentIDs.contains { media.contains($0) }
    }
}
