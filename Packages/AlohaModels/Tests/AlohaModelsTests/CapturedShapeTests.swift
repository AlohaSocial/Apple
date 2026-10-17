// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaModels

/// Every entity of the captured-shape corpus decodes whole, with the values
/// the server meant (docs/12 §2, "from real fixture JSON").
@Suite("Captured server shapes")
struct CapturedShapeTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try AlohaJSON.decoder.decode(type, from: Data(json.utf8))
    }

    @Test("An Aloha Social account, with its own keys and a date-only last post")
    func alohaAccount() throws {
        let account = try decode(Account.self, CapturedShapes.alohaAccount)
        #expect(account.id == "184")
        #expect(account.acct == "frank")
        #expect(account.followersCount == 1204)
        #expect(account.pronouns == "he/him")
        // An empty support link is absence, as an empty avatar is.
        #expect(account.supportLink == nil)
        // `last_status_at` is a calendar date on the wire, not a timestamp.
        let lastPost = try #require(account.lastStatusAt)
        let day = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC") ?? .gmt, from: lastPost)
        #expect(day.year == 2026 && day.month == 10 && day.day == 16)
        #expect(account.fields.count == 2)
        #expect(account.fields[1].isVerified)
        #expect(account.emojis.map(\.shortcode) == ["hibiscus"])
    }

    @Test("A post written on Aloha Social decodes with every extension it carries")
    func alohaLocalStatus() throws {
        let status = try decode(Status.self, CapturedShapes.alohaLocalStatus)
        #expect(status.id == "1129384756")
        #expect(status.visibility == .public)
        #expect(status.favourited)
        #expect(status.quotesCount == 2)
        #expect(status.viewCount == 87)
        #expect(status.replyPolicy == "followers,mentioned")
        #expect(status.quoteApproval?.automatic == ["followers"])
        #expect(status.quoteApproval?.currentUser == "automatic")
        #expect(status.interactionPolicy == nil)
        #expect(status.poll == nil)
        #expect(status.application == nil)
        #expect(status.filtered?.isEmpty == true)
        #expect(status.reactions?.first?.count == 4)
        let place = try #require(status.place)
        #expect(place.name == "Hilo")
        #expect(abs((place.longitude ?? 0) - -155.0885) < 0.0001)
        let media = try #require(status.mediaAttachments.first)
        #expect(media.type == .image)
        #expect(media.meta?.original?.width == 4032)
        #expect(media.description == "Boats in a calm harbour under an orange sky")
        #expect(status.account.acct == "frank")
    }

    @Test("A federated post keeps the origin's interaction policy and reply state")
    func alohaFederatedStatus() throws {
        let status = try decode(Status.self, CapturedShapes.alohaFederatedStatus)
        #expect(status.visibility == .unlisted)
        #expect(status.sensitive)
        #expect(status.spoilerText == "Water, lots of it")
        #expect(status.language == nil)
        #expect(status.inReplyToID == "1129384756")
        #expect(status.interactionPolicy == ["reply": true, "boost": false, "like": true])
        #expect(status.canHide == true)
        #expect(status.hiddenByAuthor == false)
        #expect(status.aiGenerated)
        #expect(status.interest?.reason == "interest")
        #expect(status.editedAt != nil)
        // Kept on the origin: no local URL yet, a remote one, and no meta.
        let media = try #require(status.mediaAttachments.first)
        #expect(media.type == .video)
        #expect(media.url == nil)
        #expect(media.remoteURL != nil)
        #expect(media.meta == nil)
        // The author: empty strings where a picture would be, and a count
        // that arrived as a string.
        #expect(status.account.avatar == nil)
        #expect(status.account.followersCount == 17)
    }

    @Test("A mastodon.social post with a card, a poll and an application")
    func mastodonStatus() throws {
        let status = try decode(Status.self, CapturedShapes.mastodonStatus)
        #expect(status.id == "115377001234567890")
        #expect(status.language == "de")
        #expect(status.application?.name == "Web")
        #expect(status.quoteApproval?.automatic == ["public"])
        let poll = try #require(status.poll)
        #expect(poll.options.map(\.title) == ["This", "That"])
        #expect(poll.votesCount == 42)
        let card = try #require(status.card)
        #expect(card.title == "An article")
        #expect(card.image == nil)
        #expect(status.account.lastStatusAt != nil)
    }

    @Test("Aloha Social's own notification kind arrives as itself")
    func alohaNotification() throws {
        let notification = try decode(MastodonNotification.self, CapturedShapes.alohaStoryReaction)
        #expect(notification.type == .storyReaction)
        #expect(notification.status == nil)
        #expect(notification.account.acct == "frank")
    }

    @Test("A grouped-API mention carries its post")
    func mastodonNotification() throws {
        let notification = try decode(MastodonNotification.self, CapturedShapes.mastodonMention)
        #expect(notification.type == .mention)
        #expect(notification.status?.id == "115377001234567890")
    }

    @Test("A page of every captured post decodes without a single failure")
    func wholePage() throws {
        let page =
            "["
            + [
                CapturedShapes.alohaLocalStatus, CapturedShapes.alohaFederatedStatus,
                CapturedShapes.mastodonStatus, CapturedShapes.statusWithNumericIDsAndNoPoll,
            ].joined(separator: ",") + "]"
        let decoded = try decode(LossyArray<Status>.self, page)
        #expect(decoded.failures.isEmpty)
        #expect(decoded.elements.count == 4)
    }

    // MARK: - docs/12's malformed cases, inside whole entities

    @Test("`meta` sent as an empty list is no metadata, not a failed attachment")
    func metaAsList() throws {
        let media = try decode(MediaAttachment.self, CapturedShapes.attachmentWithListMeta)
        #expect(media.meta == nil)
        #expect(media.description == nil || media.description == "")
    }

    @Test("Numeric ids, an absent poll and an empty avatar in one post")
    func numericIDsNoPollEmptyAvatar() throws {
        let status = try decode(Status.self, CapturedShapes.statusWithNumericIDsAndNoPoll)
        #expect(status.id == "4242")
        #expect(status.inReplyToID == "4241")
        #expect(status.inReplyToAccountID == "7")
        #expect(status.poll == nil)
        #expect(status.account.id == "7")
        #expect(status.account.avatar == nil)
    }
}
