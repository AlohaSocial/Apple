// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import Foundation
import Testing

@testable import AlohaUI

@Suite("Failures of confirmed actions are said, not swallowed")
@MainActor
struct ActionFailureTests {
    private func scheduled(_ id: String, inHours hours: Double) throws -> ScheduledStatus {
        let date = Date(timeIntervalSince1970: 1_800_000_000 + hours * 3600)
        let json = """
            {"id": "\(id)", "scheduled_at": "\(date.ISO8601Format())",
             "media_attachments": [], "params": {"text": "post \(id)"}}
            """
        return try AlohaJSON.decoder.decode(ScheduledStatus.self, from: Data(json.utf8))
    }

    @Test("A refused cancel puts the post back in the order posts go out")
    func refusedCancelIsRestoredInOrder() throws {
        let first = try scheduled("1", inHours: 1)
        let second = try scheduled("2", inHours: 2)
        let third = try scheduled("3", inHours: 3)

        // 2 was swiped away, the server refused it.
        let restored = ScheduledPostsView.restoring([second], into: [first, third])
        #expect(restored.map(\.id) == ["1", "2", "3"])
    }

    @Test("Restoring never doubles a post that is still listed")
    func restoringDoesNotDuplicate() throws {
        let first = try scheduled("1", inHours: 1)
        let restored = ScheduledPostsView.restoring([first], into: [first])
        #expect(restored.map(\.id) == ["1"])
    }

    @Test("The message says what did not happen, then the server's reason")
    func failureMessageLeadsWithOutcome() {
        let fallback = "The block did not go through. They can still see and reach you."
        let withReason = StatusActions.failureMessage(
            APIError.forbidden(message: "Not allowed here"), fallback: fallback)
        #expect(withReason.hasPrefix(fallback))
        #expect(withReason.count > fallback.count)

        let withoutReason = StatusActions.failureMessage(URLError(.timedOut), fallback: fallback)
        #expect(withoutReason == fallback)
    }

    @Test("Block and mute go to the routes that block and mute")
    func moderationRoutes() {
        let block = StatusActions.moderationEndpoint(.block, account: "42")
        let mute = StatusActions.moderationEndpoint(.mute, account: "42")
        #expect(block.path.hasSuffix("accounts/42/block"))
        #expect(mute.path.hasSuffix("accounts/42/mute"))
    }

    // MARK: - Optimistic favourites, boosts and bookmarks

    private let alice = Account(id: "a", username: "alice", acct: "alice")

    @Test("A favourite shows at once: the flag and the count move together")
    func optimisticFavourite() throws {
        var post = Status(id: "1", account: alice)
        post.favouritesCount = 4
        let liked = try #require(StatusActions.optimisticCopy(of: post, for: .favourite))
        #expect(liked.favourited)
        #expect(liked.favouritesCount == 5)

        let unliked = try #require(StatusActions.optimisticCopy(of: liked, for: .unfavourite))
        #expect(!unliked.favourited)
        #expect(unliked.favouritesCount == 4)
    }

    @Test("Undoing never takes a count below zero")
    func optimisticCountFloor() throws {
        var post = Status(id: "1", account: alice)
        post.reblogged = true
        post.reblogsCount = 0
        let undone = try #require(StatusActions.optimisticCopy(of: post, for: .unreblog))
        #expect(!undone.reblogged)
        #expect(undone.reblogsCount == 0)
    }

    @Test("Bookmark and mute flip their flag; a pin waits for the server")
    func optimisticFlags() throws {
        let post = Status(id: "1", account: alice)
        #expect(try #require(StatusActions.optimisticCopy(of: post, for: .bookmark)).bookmarked)
        #expect(try #require(StatusActions.optimisticCopy(of: post, for: .mute)).muted)
        #expect(StatusActions.optimisticCopy(of: post, for: .pin) == nil)
    }

    /// Mastodon moves counts asynchronously: the answer to a favourite can
    /// carry the flag and the count from before it.
    @Test("A server answer with the flag but not yet the count keeps the count")
    func reconcileLaggingCount() throws {
        var post = Status(id: "1", account: alice)
        post.favouritesCount = 4
        let optimistic = try #require(StatusActions.optimisticCopy(of: post, for: .favourite))
        var answer = post
        answer.favourited = true
        let settled = StatusActions.reconciled(answer, original: post, optimistic: optimistic)
        #expect(settled.favourited)
        #expect(settled.favouritesCount == 5)
    }

    @Test("Otherwise the server's answer is taken as it is")
    func reconcileTakesServer() throws {
        var post = Status(id: "1", account: alice)
        post.favouritesCount = 4
        let optimistic = try #require(StatusActions.optimisticCopy(of: post, for: .favourite))
        var answer = post
        answer.favourited = true
        answer.favouritesCount = 9
        #expect(
            StatusActions.reconciled(answer, original: post, optimistic: optimistic)
                .favouritesCount == 9)

        // The server says it did not take: its word stands.
        let refused = StatusActions.reconciled(post, original: post, optimistic: optimistic)
        #expect(!refused.favourited)
        #expect(refused.favouritesCount == 4)
    }

    @Test("Each toggle names what did not happen")
    func toggleFailureMessages() {
        let actions: [Endpoint.StatusAction] = [
            .favourite, .unfavourite, .reblog, .unreblog, .bookmark, .unbookmark, .mute,
            .unmute, .pin, .unpin,
        ]
        let messages = Set(actions.map(StatusActions.toggleFailure))
        #expect(messages.count == actions.count)
    }
}
