// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AppIntents
import Foundation

/// "Reply to my latest mention": Siri reads the newest post that mentions
/// the account, asks what to say, reads the reply back and posts it only
/// once it is confirmed (docs/09 §7).
///
/// No assistant schema fits: the messages domain's `sendMessage` is a
/// private message to people, and this is a public reply in a thread.
public struct ReplyToLatestMentionIntent: AppIntent {
    public static let title = LocalizedStringResource(
        "Reply to my latest mention", comment: "App Intent title")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Reads the newest post that mentions you and posts your reply to it.",
            comment: "App Intent description"))
    public static let openAppWhenRun = false
    /// A reply is speech under somebody's name, and the mention it answers
    /// can be followers-only: neither belongs to whoever holds a locked phone.
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    /// Asked for only after the mention has been read out, so the reply is
    /// spoken knowing what it answers. Set in Shortcuts, it is used as is.
    @Parameter(title: LocalizedStringResource("Reply", comment: "App Intent parameter"))
    public var text: String?

    /// Left empty, the account the app has active.
    @Parameter(title: LocalizedStringResource("Account", comment: "App Intent parameter"))
    public var account: SignedInAccountEntity?

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<PostEntity>
        & ProvidesDialog
    {
        guard let context = await IntentContext.current(accountID: account?.id) else {
            throw IntentError.noAccount
        }
        let page = try await context.client.decode(
            LossyArray<MastodonNotification>.self,
            from: Endpoint.notifications.flat(limit: 5, types: ["mention"]))
        guard let mention = MentionReply.latest(in: page.elements) else {
            throw IntentError.noMention
        }
        let author = mention.displayed.account.bestDisplayName
        let said = SpokenPosts.text(of: mention)

        var typed = MentionReply.trimmed(text)
        if typed.isEmpty {
            let answer: String? = try await $text.requestValue(
                IntentDialog(
                    LocalizedStringResource(
                        "\(author) said: “\(said)” What's your reply?",
                        comment:
                            "Siri reads the latest mention, then asks for the reply to it")))
            typed = MentionReply.trimmed(answer)
        }
        guard !typed.isEmpty else { throw IntentError.emptyReply }

        // Addressed, and as restrictive, as the composer would make it: a
        // reply without the people in the thread reaches nobody elsewhere.
        var draft = NotificationResponder.replyDraft(
            typed: typed, to: mention, viewerHandle: context.viewerAcct,
            defaultVisibility: context.defaultVisibility)
        try await requestConfirmation(
            actionName: .post,
            dialog: IntentDialog(
                LocalizedStringResource(
                    "Reply to \(author) as \(context.handle)? \(PostStatusIntent.preview(of: draft.text))",
                    comment: "Siri asks before posting a reply; the account and the reply follow")
            ))

        // Derived from what is posted, as a Shortcut's post is, so a Siri
        // retry comes back as the reply already made rather than a second.
        draft.idempotencyKey = PostStatusIntent.idempotencyKey(
            accountID: context.accountID, text: draft.text, visibility: draft.visibility,
            inReplyToID: draft.inReplyToID)
        let posted = try await context.client.decode(
            Status.self, from: Endpoint.composing.post(draft))
        await IntentContext.notePosted(posted, accountID: context.accountID)
        return .result(
            value: PostEntity(posted),
            dialog: IntentDialog(
                LocalizedStringResource(
                    "Replied to \(author).", comment: "Siri answer after posting a reply")))
    }
}

/// The pure parts of replying to a mention, apart from the intent so they
/// can be tested without Siri.
nonisolated enum MentionReply {
    /// The newest mention that still has a post to answer.
    static func latest(in notifications: [MastodonNotification]) -> Status? {
        notifications.lazy.compactMap(\.status).first
    }

    static func trimmed(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension SpokenPosts {
    /// What Siri reads of one post: its words, or only its content warning
    /// where it has one — said aloud is said to the room.
    nonisolated static func text(of status: Status) -> String {
        let target = status.displayed
        let text =
            target.spoilerText.isEmpty
            ? IntentText.plain(target.content)
            : String(
                localized: "Content warning: \(target.spoilerText)",
                comment: "Siri reads a post's content warning instead of the post")
        guard text.count > characters else { return text }
        return String(text.prefix(characters)) + "…"
    }
}
