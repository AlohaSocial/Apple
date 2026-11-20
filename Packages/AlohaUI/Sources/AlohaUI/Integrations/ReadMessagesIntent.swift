// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AppIntents
import Foundation

/// "Read my messages": the newest unread direct messages, who sent each and
/// what it says, spoken by Siri without the app opening (docs/09 §7).
///
/// Nothing is marked read. Siri can be cut off half-way, and a message
/// somebody has not heard is still unread in the app, as it is on the
/// widget and the watch.
///
/// No assistant schema fits: the messages domain has sending, drafting and
/// marking read, but no intent that returns messages to be read out.
public struct ReadMessagesIntent: AppIntent {
    public static let title = LocalizedStringResource(
        "Read my messages", comment: "App Intent title")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Reads your newest unread direct messages aloud.", comment: "App Intent description"))
    public static let openAppWhenRun = false
    /// Direct messages are the most private thing in the app: a locked
    /// phone does not read them to whoever is holding it.
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(
        title: LocalizedStringResource("How many", comment: "App Intent parameter"), default: 3)
    public var count: Int

    /// Left empty, the account the app has active.
    @Parameter(title: LocalizedStringResource("Account", comment: "App Intent parameter"))
    public var account: SignedInAccountEntity?

    public init() {}

    /// The messages as posts, so a Shortcut can open or pass one on; Siri
    /// reads each one's sender and text.
    public func perform() async throws -> some IntentResult & ReturnsValue<[PostEntity]>
        & ProvidesDialog
    {
        guard let context = await IntentContext.current(accountID: account?.id) else {
            throw IntentError.noAccount
        }
        let conversations = try await context.client.decode(
            LossyArray<Conversation>.self, from: Endpoint.timelines.conversations(limit: 20)
        ).elements
        let unread = SpokenMessages.unread(conversations)
        guard !unread.isEmpty else {
            return .result(
                value: [],
                dialog: IntentDialog(
                    LocalizedStringResource(
                        "No unread messages.",
                        comment: "Siri answer when no direct message is unread")))
        }
        let read = Array(unread.prefix(min(max(count, 1), SpokenMessages.maximumCount)))
        let spoken = SpokenMessages.summary(of: read)
        return .result(
            value: read.compactMap { $0.lastStatus.map(PostEntity.init) },
            dialog: IntentDialog(
                full: LocalizedStringResource(
                    "^[\(unread.count) unread conversation](inflect: true). \(spoken)",
                    comment: "Siri answer reading the newest unread direct messages aloud"),
                supporting: LocalizedStringResource(
                    "^[\(unread.count) unread conversation](inflect: true).",
                    comment: "Siri answer shown above the unread direct messages")))
    }
}

/// Direct messages as one stretch of speech: the sender of each newest
/// message, and enough of it to know what it is about.
nonisolated enum SpokenMessages {
    /// More than this is a list to look at, not something to listen to.
    static let maximumCount = 10

    /// The conversations with something unread, newest message first.
    /// One whose last message is gone has nothing to read out.
    static func unread(_ conversations: [Conversation]) -> [Conversation] {
        conversations
            .filter { $0.unread && $0.lastStatus != nil }
            .sorted {
                ($0.lastStatus?.createdAt ?? .distantPast)
                    > ($1.lastStatus?.createdAt ?? .distantPast)
            }
    }

    static func summary(of conversations: [Conversation]) -> String {
        conversations.compactMap { conversation in
            conversation.lastStatus.map { status in
                "\(status.account.bestDisplayName): \(SpokenPosts.text(of: status))"
            }
        }.joined(separator: " … ")
    }
}
