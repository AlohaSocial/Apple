// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaModels

// Fixtures are the shapes Aloha Social's `Stream::exportAsLocal` and
// `Person::exportAsLocal` write, and what a stock Mastodon sends instead —
// which is to say, nothing at all for any of these fields.

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try AlohaJSON.decoder.decode(T.self, from: Data(json.utf8))
}

private let account = #"{"id": "1", "username": "alice", "acct": "alice"}"#

private func status(_ extra: String) -> String {
    #"{"id": "10", "created_at": "2026-10-01T10:00:00.000Z", "account": "#
        + account + (extra.isEmpty ? "" : ", " + extra) + "}"
}

@Suite("Aloha Social status extras")
struct StatusExtrasDecodingTests {

    @Test("Every extra decodes from the server's own export")
    func allExtras() throws {
        let decoded = try decode(
            Status.self,
            status(
                """
                "reply_policy": "followers,mentioned",
                "hidden_by_author": false, "can_hide": true,
                "reply_approval": {"policy": "manual", "state": "pending"},
                "ai_generated": true,
                "bluesky": {"uri": "at://did:plc:x/app.bsky.feed.post/1",
                            "url": "https://bsky.app/profile/a.bsky.social/post/1",
                            "labels": [{"src": "did:plc:labeler", "val": "nudity"}, {"src": 3}]},
                "interest": {"tags": ["cats", "photography"], "reason": "interest"},
                "quotes_count": 4, "view_count": "12"
                """))
        #expect(decoded.replyPolicy == "followers,mentioned")
        // A set reads as its widest member: that is who is let in.
        #expect(decoded.replyAudience == .followers)
        #expect(decoded.hiddenByAuthor == false)
        #expect(decoded.canHide == true)
        #expect(decoded.replyApproval == ReplyApproval(policy: "manual", state: "pending"))
        #expect(decoded.aiGenerated)
        #expect(decoded.bluesky?.uri == "at://did:plc:x/app.bsky.feed.post/1")
        // The malformed label costs that label only.
        #expect(decoded.bluesky?.labels == [.init(source: "did:plc:labeler", value: "nudity")])
        #expect(
            decoded.interest == StatusInterest(tags: ["cats", "photography"], reason: "interest"))
        #expect(decoded.quotesCount == 4)
        #expect(decoded.viewCount == 12)
    }

    @Test("The server's nulls are nil, not a failure")
    func nulls() throws {
        let decoded = try decode(
            Status.self,
            status(
                """
                "reply_policy": null, "hidden_by_author": null, "can_hide": null,
                "reply_approval": null, "ai_generated": false, "bluesky": null,
                "interest": null, "view_count": null
                """))
        #expect(decoded.replyPolicy == nil)
        #expect(decoded.replyAudience == nil)
        #expect(decoded.hiddenByAuthor == nil)
        #expect(decoded.isHiddenByAuthor == false)
        #expect(decoded.canHide == nil)
        #expect(decoded.replyApproval == nil)
        #expect(!decoded.aiGenerated)
        #expect(decoded.bluesky == nil)
        #expect(decoded.interest == nil)
        #expect(decoded.viewCount == nil)
    }

    @Test("A stock Mastodon status has none of them")
    func absent() throws {
        let decoded = try decode(Status.self, status(""))
        #expect(decoded.replyPolicy == nil)
        #expect(!decoded.aiGenerated)
        #expect(decoded.quotesCount == nil)
        #expect(decoded.viewCount == nil)
        #expect(decoded.bluesky == nil)
    }

    @Test("A hidden reply is marked hidden")
    func hiddenReply() throws {
        let decoded = try decode(Status.self, status(#""hidden_by_author": true"#))
        #expect(decoded.isHiddenByAuthor)
    }

    @Test("The extras survive the store's own round trip")
    func roundTrip() throws {
        let original = try decode(
            Status.self,
            status(
                #""reply_policy": "nobody", "ai_generated": true, "quotes_count": 2, "interest": {"tags": ["x"], "reason": "popular"}"#
            ))
        let data = try AlohaJSON.encoder.encode(original)
        let again = try AlohaJSON.decoder.decode(Status.self, from: data)
        #expect(again.replyPolicy == "nobody")
        #expect(again.aiGenerated)
        #expect(again.quotesCount == 2)
        #expect(again.interest?.reason == "popular")
    }

    @Test("An attachment says it was made with AI")
    func mediaAIGenerated() throws {
        let labelled = try decode(
            MediaAttachment.self, #"{"id": "1", "type": "image", "ai_generated": true}"#)
        let plain = try decode(MediaAttachment.self, #"{"id": "2", "type": "image"}"#)
        #expect(labelled.aiGenerated)
        #expect(!plain.aiGenerated)
    }
}

@Suite("Reply policy")
struct ReplyPolicyTests {
    @Test(
        "A wire value reads as its widest audience",
        arguments: [
            ("everyone", ReplyPolicy.everyone),
            ("mentioned", .mentioned),
            ("following,followers", .followers),
            ("NOBODY", .nobody),
            (" mentioned , following ", .following),
        ])
    func wire(_ raw: String, _ expected: ReplyPolicy) {
        #expect(ReplyPolicy(wire: raw) == expected)
    }

    @Test("Nothing this app can draw is nil", arguments: ["", "list:7", "anyone"])
    func unknown(_ raw: String) {
        #expect(ReplyPolicy(wire: raw) == nil)
    }
}

@Suite("Aloha Social account extras")
struct AccountExtrasDecodingTests {

    @Test("Pronouns, support link, verification and Bluesky decode")
    func extras() throws {
        let decoded = try decode(
            Account.self,
            """
            {"id": "1", "username": "alice", "acct": "alice",
             "pronouns": "she/her", "support_link": "https://ko-fi.com/alice",
             "verification": {"by": "Aloha", "issuer": "did:web:aloha.example",
                              "created_at": "2026-09-01T00:00:00.000Z"},
             "bluesky": {"handle": "alice.aloha.example", "did": "did:plc:abc",
                         "url": "https://bsky.app/profile/alice.aloha.example",
                         "native": false, "active": true}}
            """)
        #expect(decoded.pronouns == "she/her")
        #expect(decoded.supportLink == URL(string: "https://ko-fi.com/alice"))
        #expect(decoded.verification?.by == "Aloha")
        #expect(decoded.verification?.createdAt != nil)
        #expect(decoded.bluesky?.displayHandle == "@alice.aloha.example")
        #expect(decoded.bluesky?.native == false)
        #expect(decoded.bluesky?.isShowable == true)
    }

    @Test("Empty strings and nulls are none")
    func empty() throws {
        let decoded = try decode(
            Account.self,
            """
            {"id": "1", "username": "alice", "acct": "alice",
             "pronouns": "", "support_link": "", "verification": null, "bluesky": null}
            """)
        #expect(decoded.pronouns == nil)
        #expect(decoded.supportLink == nil)
        #expect(decoded.verification == nil)
        #expect(decoded.bluesky == nil)
    }

    @Test("A support link that is not https is never a button")
    func insecureSupportLink() throws {
        let decoded = try decode(
            Account.self,
            #"{"id": "1", "username": "a", "acct": "a", "support_link": "javascript:alert(1)"}"#)
        #expect(decoded.supportLink == nil)
    }

    @Test("A switched-off Bluesky presence is not shown")
    func inactiveBluesky() throws {
        let decoded = try decode(
            Account.self,
            #"{"id": "1", "username": "a", "acct": "a", "bluesky": {"handle": "a.example", "active": false}}"#
        )
        #expect(decoded.bluesky?.isShowable == false)
    }

    @Test("A native Bluesky account carries its verification")
    func nativeBluesky() throws {
        let decoded = try decode(
            Account.self,
            #"{"id": "1", "username": "a", "acct": "a@bsky.brid.gy", "bluesky": {"handle": "a.bsky.social", "did": "did:plc:1", "native": true, "verified": true}}"#
        )
        #expect(decoded.bluesky?.native == true)
        #expect(decoded.bluesky?.verified == true)
        #expect(decoded.bluesky?.active == nil)
    }
}

@Suite("Aloha Social settings entities")
struct SocialSettingsDecodingTests {

    @Test("The hide switch tolerates the spellings a server uses")
    func hideSetting() throws {
        #expect(try decode(HideSetting.self, #"{"hide": true}"#).hide)
        #expect(try decode(HideSetting.self, #"{"hide": "1"}"#).hide)
        #expect(try !decode(HideSetting.self, #"{"hide": false}"#).hide)
    }

    @Test("Who may message decodes, and an unknown answer is the default")
    func directMessages() throws {
        #expect(try decode(DirectMessageSetting.self, #"{"from": "following"}"#).from == .following)
        #expect(try decode(DirectMessageSetting.self, #"{"from": "friends"}"#).from == .all)
    }

    @Test("Notification delivery decodes and encodes the server's nested shape")
    func delivery() throws {
        let json = """
            {"mode": "digest", "times": ["08:00", "18:30"],
             "passthrough": {"direct": true, "mentions_from_followed": false},
             "quiet": {"from": "22:00", "to": "07:00"}}
            """
        let decoded = try decode(NotificationDeliverySettings.self, json)
        #expect(decoded.mode == .digest)
        #expect(decoded.times == ["08:00", "18:30"])
        #expect(decoded.passthroughDirect)
        #expect(!decoded.passthroughMentionsFromFollowed)
        #expect(decoded.quietFrom == "22:00")
        #expect(decoded.quietTo == "07:00")

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded))
        let object = try #require(encoded as? [String: Any])
        let quiet = try #require(object["quiet"] as? [String: String])
        let pass = try #require(object["passthrough"] as? [String: Bool])
        #expect(object["mode"] as? String == "digest")
        #expect(quiet["from"] == "22:00")
        #expect(pass["mentions_from_followed"] == false)
    }

    @Test("A delivery setting with nothing in it is instant, without quiet hours")
    func deliveryDefaults() throws {
        let decoded = try decode(NotificationDeliverySettings.self, "{}")
        #expect(decoded.mode == .instant)
        #expect(decoded.times.isEmpty)
        #expect(decoded.quietFrom.isEmpty)
    }

    @Test("Hours go to and from the server's HH:MM")
    func wireTimes() {
        #expect(NotificationDeliverySettings.wireTime(hour: 8) == "08:00")
        #expect(NotificationDeliverySettings.wireTime(hour: 23) == "23:00")
        #expect(NotificationDeliverySettings.wireTime(hour: 30) == "23:00")
        #expect(NotificationDeliverySettings.hour(of: "07:30") == 7)
        #expect(NotificationDeliverySettings.hour(of: "") == nil)
        #expect(NotificationDeliverySettings.hour(of: "25:00") == nil)
    }

    @Test("Kept Bluesky feeds decode, and one bad feed costs only itself")
    func blueskyFeeds() throws {
        let decoded = try decode(
            BlueskyFeedList.self,
            """
            {"feeds": [
              {"uri": "at://did:plc:a/app.bsky.feed.generator/cats", "type": "feed",
               "name": "Cats", "description": "Cats.", "avatar": "", "creator": "a.bsky.social",
               "pinned": true},
              {"name": "No uri"},
              {"uri": "at://did:plc:b/app.bsky.graph.list/1", "type": "list", "name": ""}
            ]}
            """)
        #expect(decoded.feeds.count == 2)
        #expect(decoded.feeds[0].kind == .feed)
        #expect(decoded.feeds[0].pinned)
        #expect(decoded.feeds[0].avatar == nil)
        #expect(decoded.feeds[1].kind == .list)
        #expect(decoded.feeds[1].title == "at://did:plc:b/app.bsky.graph.list/1")
    }

    @Test("The Bluesky identity decodes, with and without publish_blocks")
    func identity() throws {
        let full = try decode(
            BlueskyIdentity.self,
            """
            {"handle": "alice.aloha.example", "did": "did:plc:abc",
             "url": "https://bsky.app/profile/alice.aloha.example", "state": "active",
             "active": false, "recovery_key": true, "assigned_handle": "alice.aloha.example",
             "custom_handle": "", "custom_handle_broken": false, "publish_blocks": true}
            """)
        #expect(full.handle == "alice.aloha.example")
        #expect(!full.active)
        #expect(full.recoveryKey)
        #expect(full.publishBlocks == true)

        let bare = try decode(BlueskyIdentity.self, #"{"handle": "a.example"}"#)
        #expect(bare.active)
        #expect(bare.publishBlocks == nil)
    }

    @Test("A shared moderation list decodes")
    func moderationList() throws {
        let decoded = try decode(
            [ModerationList].self,
            #"[{"uri": "at://did:plc:x/app.bsky.graph.list/9", "name": "Spam", "kind": "block", "accounts": 120}]"#
        )
        #expect(decoded.first?.kind == .block)
        #expect(decoded.first?.accounts == 120)
    }

    @Test("The policy's one-time notice decodes, and is off where absent")
    func policyNotice() throws {
        #expect(try decode(NotificationPolicy.self, #"{"notice": true}"#).notice)
        #expect(try !decode(NotificationPolicy.self, "{}").notice)
    }
}

@Suite("Reading signals")
struct InterestSignalTests {

    @Test("A signal encodes as the object the server reads")
    func encoding() throws {
        let signal = InterestSignal(
            statusID: "42", kind: .dwell, milliseconds: 4200, context: .home)
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(signal)) as? [String: Any])
        #expect(object["status_id"] as? String == "42")
        #expect(object["kind"] as? String == "dwell")
        #expect(object["ms"] as? Int == 4200)
        #expect(object["context"] as? String == "home")
    }

    @Test("Time on screen is clamped to what the server counts")
    func clamped() {
        #expect(
            InterestSignal(statusID: "1", kind: .dwell, milliseconds: 90_000, context: .home)
                .milliseconds == 30_000)
        #expect(
            InterestSignal(statusID: "1", kind: .skip, milliseconds: -5, context: .home)
                .milliseconds == 0)
    }

    @Test("Only the server's own ids are learnable")
    func learnable() {
        #expect(InterestSignal(statusID: "123", kind: .open, context: .detail).isLearnable)
        #expect(!InterestSignal(statusID: "AbC", kind: .open, context: .detail).isLearnable)
        #expect(!InterestSignal(statusID: "", kind: .open, context: .detail).isLearnable)
    }
}

@Suite("Timeline narrowing")
struct ShortsNarrowingTests {
    @Test("Shorts ask for short videos where the server narrows video")
    func shortsAskForShorts() {
        let nextcloud = ServerCapabilities(
            apiBase: URL(string: "https://example.test/")!, onlyVideoFilter: true)
        let filters = TimelineFilters.forMode(.shorts, capabilities: nextcloud)
        #expect(filters.onlyVideo)
        #expect(filters.onlyShort)
        #expect(!TimelineFilters.forMode(.video, capabilities: nextcloud).onlyShort)
    }

    @Test("A Bluesky feed has its own storage key")
    func blueskyKey() {
        #expect(TimelineSource.bluesky(feedURI: "at://x").storageKey == "bluesky:at://x")
        #expect(TimelineSource.bluesky(feedURI: "at://x").requiresViewer)
        #expect(TimelineSource.bluesky(feedURI: "at://x").pathSegment == nil)
    }
}
