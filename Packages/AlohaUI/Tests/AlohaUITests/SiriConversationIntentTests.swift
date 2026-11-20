// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaUI

/// "Reply to my latest mention" and "Read my messages": what is read out,
/// what is answered, and that a retried reply is the same post.
@Suite("Siri: mentions and messages")
struct SiriConversationIntentTests {
    private let me = Account(id: "me", username: "me", acct: "me", displayName: "Me")
    private let ana = Account(
        id: "ana", username: "ana", acct: "ana@other.example", displayName: "Ana")
    private let bo = Account(id: "bo", username: "bo", acct: "bo", displayName: "Bo")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The latest mention is the newest one that still has its post")
    func latestMention() {
        let gone = MastodonNotification(id: "1", type: .mention, account: ana, status: nil)
        let newest = MastodonNotification(
            id: "2", type: .mention, account: ana, status: Status(id: "20", account: ana))
        let older = MastodonNotification(
            id: "3", type: .mention, account: bo, status: Status(id: "10", account: bo))
        #expect(MentionReply.latest(in: [gone, newest, older])?.id == "20")
        #expect(MentionReply.latest(in: [gone]) == nil)
    }

    @Test("Siri reads a content warning rather than the post behind it")
    func spokenText() {
        let plain = Status(id: "1", content: "<p>Hello <b>you</b></p>", account: ana)
        #expect(SpokenPosts.text(of: plain) == "Hello you")

        let warned = Status(
            id: "2", content: "<p>Spoilers</p>", spoilerText: "Film ending", account: ana)
        let spoken = SpokenPosts.text(of: warned)
        #expect(spoken.contains("Film ending"))
        #expect(!spoken.contains("Spoilers"))

        let long = Status(
            id: "3", content: String(repeating: "word ", count: 80), account: ana)
        #expect(SpokenPosts.text(of: long).count == SpokenPosts.characters + 1)
    }

    @Test("A reply addresses the author, keeps the thread's restriction and answers the post")
    func replyDraft() {
        let mention = Status(
            id: "20", content: "<p>@me hi</p>", visibility: .private, account: ana,
            mentions: [.init(id: "me", username: "me", acct: "me")])
        let draft = NotificationResponder.replyDraft(
            typed: "Hi back", to: mention, viewerHandle: "me", defaultVisibility: .public)
        #expect(draft.text == "@ana@other.example Hi back")
        #expect(draft.visibility == .private)
        #expect(draft.inReplyToID == "20")
    }

    @Test("A retried reply carries the same key; the same words to another post do not")
    func replyKey() {
        let account = UUID()
        let first = PostStatusIntent.idempotencyKey(
            accountID: account, text: "Hi", visibility: .public, inReplyToID: "20", now: now)
        let retry = PostStatusIntent.idempotencyKey(
            accountID: account, text: "Hi", visibility: .public, inReplyToID: "20",
            now: now.addingTimeInterval(20))
        let elsewhere = PostStatusIntent.idempotencyKey(
            accountID: account, text: "Hi", visibility: .public, inReplyToID: "21", now: now)
        let notAReply = PostStatusIntent.idempotencyKey(
            accountID: account, text: "Hi", visibility: .public, now: now)
        #expect(first == retry)
        #expect(first != elsewhere)
        #expect(first != notAReply)
    }

    @Test("Only what Siri was given is trimmed to nothing")
    func trimming() {
        #expect(MentionReply.trimmed(nil).isEmpty)
        #expect(MentionReply.trimmed("  \n").isEmpty)
        #expect(MentionReply.trimmed(" Yes ") == "Yes")
    }

    @Test("Unread conversations are read newest first, each by its last sender")
    func unreadMessages() {
        let conversations = [
            Conversation(
                id: "a", accounts: [ana], unread: true,
                lastStatus: Status(
                    id: "1", createdAt: now.addingTimeInterval(-600), content: "<p>Lunch?</p>",
                    visibility: .direct, account: ana)),
            Conversation(
                id: "b", accounts: [bo], unread: false,
                lastStatus: Status(id: "2", createdAt: now, content: "Read", account: bo)),
            Conversation(
                id: "c", accounts: [bo, ana], unread: true,
                lastStatus: Status(
                    id: "3", createdAt: now, content: "<p>On my way</p>", visibility: .direct,
                    account: bo)),
            Conversation(id: "d", accounts: [ana], unread: true, lastStatus: nil),
        ]
        let unread = SpokenMessages.unread(conversations)
        #expect(unread.map(\.id) == ["c", "a"])
        #expect(SpokenMessages.summary(of: unread) == "Bo: On my way … Ana: Lunch?")
    }
}
