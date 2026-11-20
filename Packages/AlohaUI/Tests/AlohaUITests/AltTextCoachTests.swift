// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaUI

@Suite("The alt-text coach")
struct AltTextCoachTests {
    private let alice = Account(id: "a", username: "alice", acct: "alice")

    private func picture(_ id: String, _ description: String? = nil) -> MediaAttachment {
        MediaAttachment(id: id, type: .image, description: description)
    }

    @Test("It nudges once, only when switched on, and only for something undescribed")
    func nudgesOnce() {
        let bare = [picture("1")]
        let described = [picture("1", "A cat on a windowsill")]
        #expect(ComposerModel.shouldNudge(enabled: true, alreadyNudged: false, attachments: bare))
        #expect(!ComposerModel.shouldNudge(enabled: true, alreadyNudged: true, attachments: bare))
        #expect(!ComposerModel.shouldNudge(enabled: false, alreadyNudged: false, attachments: bare))
        #expect(
            !ComposerModel.shouldNudge(enabled: true, alreadyNudged: false, attachments: described))
        // A description of nothing but spaces is no description.
        #expect(
            ComposerModel.shouldNudge(
                enabled: true, alreadyNudged: false, attachments: [picture("1", "  ")]))
    }

    @Test("A suggestion waiting for review asks again, even with the reminder off")
    func suggestionsAskAgain() {
        let bare = [picture("1")]
        #expect(
            ComposerModel.shouldNudge(
                enabled: true, alreadyNudged: true, attachments: bare, awaitingReview: ["1"]))
        #expect(
            ComposerModel.shouldNudge(
                enabled: false, alreadyNudged: false, attachments: bare, awaitingReview: ["1"]))
        // Accepted, it is a description, and nothing is left to say.
        #expect(
            !ComposerModel.shouldNudge(
                enabled: true, alreadyNudged: false, attachments: [picture("1", "A wave")],
                awaitingReview: ["1"]))
        // A suggestion for one picture does not hide another's silence.
        #expect(
            !ComposerModel.shouldNudge(
                enabled: true, alreadyNudged: true, attachments: [picture("1"), picture("2")],
                awaitingReview: []))
    }

    @Test("The server's figure is read as it is sent, under either key")
    func fromServer() {
        let current = AccountStatistics(
            media: NumberMap(values: ["images": 10, "described": 7, "described_share": 70]))
        #expect(AltTextCoverage(statistics: current)?.share == 0.7)
        #expect(AltTextCoverage(statistics: current)?.source == .server)
        let earlier = AccountStatistics(media: NumberMap(values: ["pictures": 4, "described": 1]))
        #expect(AltTextCoverage(statistics: earlier)?.pictures == 4)
        #expect(AltTextCoverage(statistics: AccountStatistics()) == nil)
    }

    @Test("Counted here: per picture, boosts and videos left out")
    func fromPosts() {
        let mine = Status(
            id: "1", account: alice,
            mediaAttachments: [
                picture("p1", "Described"), picture("p2"),
                MediaAttachment(id: "v", type: .video),
            ])
        let boosted = Status(
            id: "2", account: alice,
            reblog: Box(Status(id: "3", account: alice, mediaAttachments: [picture("p3")])))
        let coverage = AltTextCoverage(posts: [mine, boosted])
        #expect(coverage.pictures == 2)
        #expect(coverage.described == 1)
        #expect(coverage.share == 0.5)
        #expect(coverage.source == .recentPosts(1))
        #expect(AltTextCoverage(posts: []).share == nil)
    }
}
