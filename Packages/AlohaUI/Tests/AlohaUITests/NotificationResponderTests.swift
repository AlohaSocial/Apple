// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaStore
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
        // A direct message is somebody talking to you too.
        #expect(
            NotificationResponder.presentationOptions(
                forCategory: NotificationAlert.directMessageCategory
            ).contains(.banner))
    }

    @Test("A direct message wears its own category; other mentions the mention one")
    func directMessageCategory() {
        #expect(NotificationAlert.category(for: .mention, isDirect: true) == "direct")
        #expect(NotificationAlert.category(for: .mention) == "mention")
        // Only a mention can be a direct message to answer.
        #expect(NotificationAlert.category(for: .favourite, isDirect: true) == "generic")
    }

    @Test("A reply to a direct message from the Lock Screen or the watch stays direct")
    func directReplyStaysDirect() {
        let draft = NotificationResponder.replyDraft(
            typed: "on my way", to: status(visibility: .direct), viewerHandle: "me",
            defaultVisibility: .public)
        #expect(draft.visibility == .direct)
        #expect(draft.inReplyToID == "42")
        #expect(draft.text == "@alice@remote.test on my way")
    }

    @Test("A stored notification knows whether its post is a direct message")
    func payloadVisibility() throws {
        let payload = NotificationPayload(
            title: "", body: "", avatarURL: nil, accountHandle: "", statusID: "42",
            visibility: .direct)
        let data = try AlohaJSON.encoder.encode(payload)
        #expect(NotificationPayload.decode(data)?.isDirect == true)
        // Bytes an older build stored have no visibility, and are no DM.
        let older = Data(#"{"title":"","body":"","accountHandle":"","statusID":"1"}"#.utf8)
        #expect(NotificationPayload.decode(older)?.isDirect == false)
    }
}

/// Every local notification used to be silent: the one line that set a sound
/// only ever set none.
@Suite("Notification sound")
struct NotificationSoundTests {
    @Test("A mention sounds, as it does in the foreground")
    func mentionSounds() {
        #expect(LocalNotifier.sound(for: .mention) != nil)
        #expect(
            NotificationResponder.presentationOptions(forCategory: "mention").contains(.sound))
    }

    @Test("Favourites, boosts and follows arrive silently")
    func passiveKindsAreSilent() {
        for kind in [NotificationKind.favourite, .reblog, .follow, .poll] {
            #expect(LocalNotifier.sound(for: kind) == nil)
        }
    }
}
