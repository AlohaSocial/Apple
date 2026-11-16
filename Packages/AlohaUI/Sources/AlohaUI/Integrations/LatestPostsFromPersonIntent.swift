// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AppIntents
import Foundation

/// "What's new from <person>?": somebody's latest posts, read out by Siri
/// and handed on as posts in Shortcuts.
///
/// The people offered are the ones the account follows
/// (`PersonEntityQuery.suggestedEntities`), which is also what Siri learns
/// the names from; anybody the server can find can be named in Shortcuts.
public struct LatestPostsFromPersonIntent: AppIntent {
    public static let title = LocalizedStringResource(
        "What's new from someone", comment: "App Intent title")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "The latest posts of someone you follow.", comment: "App Intent description"))
    public static let openAppWhenRun = false
    /// Followers-only posts can be among them, which a locked phone must
    /// not read aloud to whoever holds it.
    public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: LocalizedStringResource("Person", comment: "App Intent parameter"))
    public var person: PersonEntity

    @Parameter(
        title: LocalizedStringResource("How many", comment: "App Intent parameter"), default: 3)
    public var count: Int

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<[PostEntity]>
        & ProvidesDialog
    {
        // The person was found through the active account, and their id is
        // that server's; it means nothing on another one.
        guard let context = await IntentContext.current() else { throw IntentError.noAccount }
        let statuses = try await context.client.decode(
            LossyArray<Status>.self,
            from: Endpoint.timelines.timeline(
                .account(id: person.id, includeReplies: false, onlyMedia: false),
                limit: min(max(count, 1), 20))
        ).elements
        let posts = statuses.map(PostEntity.init)
        guard !posts.isEmpty else {
            return .result(
                value: [],
                dialog: IntentDialog(
                    LocalizedStringResource(
                        "\(person.name) hasn't posted anything lately.",
                        comment: "Siri answer when a person has no recent posts")))
        }
        let spoken = SpokenPosts.summary(of: posts, includingAuthor: false)
        return .result(
            value: posts,
            dialog: IntentDialog(
                LocalizedStringResource(
                    "The latest from \(person.name): \(spoken)",
                    comment: "Siri answer reading a person's latest posts")))
    }
}

/// Posts as one stretch of speech: who said it where that matters, and
/// enough of each to know what it is about. Three at most — Siri reading
/// twenty posts aloud is nobody's idea of an answer; the rest are in the
/// result.
nonisolated enum SpokenPosts {
    static let spokenCount = 3
    static let characters = 140

    static func summary(of posts: [PostEntity], includingAuthor: Bool) -> String {
        posts.prefix(spokenCount).map { post in
            let text =
                post.text.count > characters
                ? String(post.text.prefix(characters)) + "…" : post.text
            return includingAuthor ? "\(post.author): \(text)" : text
        }.joined(separator: " … ")
    }
}
