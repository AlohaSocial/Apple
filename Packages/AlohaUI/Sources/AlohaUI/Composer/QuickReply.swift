// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import Foundation

/// The composer's rules for a post written on one line: who it addresses,
/// who can see it, and whether it fits.
///
/// The thread's reply bar and the Mac's menu-bar field send without opening
/// the composer, so they must not answer differently from it. The quick
/// field used to mention only the post's author and to copy the post's
/// visibility as it was; the composer mentions everyone the post does and
/// never answers less privately than the reader's default
/// (`ComposerModel.prepare`). One set of rules, here, from the same
/// `Status` helpers the composer and the lock-screen reply use — including
/// the lock-screen reply's: an answer to a post behind a content warning is
/// sent behind the same warning (`NotificationResponder.replyDraft`).
nonisolated struct QuickReply: Sendable {
    /// The post answered; nil for a new post.
    let replyTo: Status?
    /// The reader's own handle, which a reply does not mention.
    let viewerHandle: String?
    let defaultVisibility: Visibility
    let limits: ServerLimits

    /// What goes to the server: the words as typed, with every handle the
    /// composer would have prefilled in front unless the words already name
    /// it.
    func postText(_ typed: String) -> String {
        guard let replyTo else { return typed.trimmingCharacters(in: .whitespacesAndNewlines) }
        return replyTo.replyText(typed, excluding: viewerHandle)
    }

    /// A reply is never less private than what it answers.
    var visibility: Visibility {
        replyTo?.replyVisibility(default: defaultVisibility) ?? defaultVisibility
    }

    /// The warning the answered post was written under, carried over.
    var spoilerText: String? {
        guard let warning = replyTo?.displayed.spoilerText, !warning.isEmpty else { return nil }
        return warning
    }

    /// Characters left, counted as the composer counts them — mentions and
    /// the warning included, a URL at the server's flat rate.
    func remaining(_ typed: String) -> Int {
        CharacterCount.remaining(
            text: postText(typed), spoilerText: spoilerText ?? "", limits: limits)
    }

    /// What is sent.
    func post(_ typed: String, language: String?, idempotencyKey: String) -> StatusPost {
        StatusPost(
            text: postText(typed), visibility: visibility, spoilerText: spoilerText,
            sensitive: replyTo?.displayed.sensitive ?? false, language: language,
            inReplyToID: replyTo?.displayed.id, idempotencyKey: idempotencyKey)
    }

    func canSend(_ typed: String) -> Bool {
        !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && remaining(typed) >= 0
    }

    /// Whether the count is worth showing yet: only near the limit, where it
    /// tells the writer something.
    func showsCount(_ typed: String) -> Bool {
        remaining(typed) <= 50
    }

    /// The text the full composer opens with when the writer asks for it:
    /// what they wrote, addressed. Empty when nothing was written, so the
    /// composer prefills the mentions itself, as it does for any reply.
    func composerText(_ typed: String) -> String {
        guard !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return postText(typed)
    }
}
