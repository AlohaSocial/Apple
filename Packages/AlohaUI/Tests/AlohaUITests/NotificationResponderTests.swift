// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing
import UserNotifications

@testable import AlohaUI

/// A reply typed on the lock screen used to be thrown away: the action mapped
/// to "open the composer", which nothing on a lock screen can do. These pin
/// what is sent instead.
@Suite("Notification responses")
@MainActor
struct NotificationResponderTests {
    private let author = Account(id: "a", username: "alice", acct: "alice@remote.test")

    private func status(
        visibility: Visibility = .public, spoiler: String = "", mentions: [Status.Mention] = []
    ) -> Status {
        Status(
            id: "42", spoilerText: spoiler, visibility: visibility, account: author,
            mentions: mentions)
    }

    @Test("A reply addresses the author, as the composer would")
    func replyAddsTheAuthor() {
        let text = NotificationResponder.replyText(
            typed: "Thanks!", to: status(), viewerHandle: "me")
        #expect(text == "@alice@remote.test Thanks!")
    }

    @Test("A mention the person typed themselves is not added twice")
    func typedMentionIsNotDoubled() {
        let text = NotificationResponder.replyText(
            typed: "@Alice@remote.test thanks", to: status(), viewerHandle: "me")
        #expect(text == "@Alice@remote.test thanks")
    }

    @Test("Everyone in the conversation is addressed, minus the replier")
    func replyAddressesTheConversation() {
        let mentions = [
            Status.Mention(id: "b", username: "bob", acct: "bob"),
            Status.Mention(id: "m", username: "me", acct: "me"),
        ]
        let text = NotificationResponder.replyText(
            typed: "hi", to: status(mentions: mentions), viewerHandle: "me")
        #expect(text == "@alice@remote.test @bob hi")
    }

    @Test("A reply is never less restrictive than what it answers, and keeps its warning")
    func replyDraftFollowsTheParent() {
        let draft = NotificationResponder.replyDraft(
            typed: "hi", to: status(visibility: .private, spoiler: "spoilers"),
            viewerHandle: "me", defaultVisibility: .public)
        #expect(draft.visibility == .private)
        #expect(draft.spoilerText == "spoilers")
        #expect(draft.inReplyToID == "42")
    }

    @Test("A tap opens the post, or the notifications screen when there is none")
    func tapRoute() {
        #expect(NotificationResponder.route(forTapOn: "7") == .thread(statusID: "7"))
        #expect(NotificationResponder.route(forTapOn: nil) == .notifications)
    }

    @Test("An empty status id in the payload is no status")
    func emptyStatusIDIsNone() {
        let reply = NotificationReply(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: ["accountID": UUID().uuidString, "statusID": ""], typedText: nil)
        #expect(reply.statusID == nil)
        #expect(reply.accountID != nil)
    }

    @Test("Only a mention interrupts while the app is in front")
    func foregroundPresentation() {
        #expect(NotificationResponder.presentationOptions(forCategory: "mention").contains(.banner))
        #expect(
            !NotificationResponder.presentationOptions(forCategory: "generic").contains(.banner))
        #expect(NotificationResponder.presentationOptions(forCategory: "generic").contains(.list))
    }
}
