// SPDX-License-Identifier: MIT

import AlohaModels
import CoreGraphics
import Foundation
import Testing

@testable import AlohaUI

@Suite("A post shared as an image shows only what the reader has seen")
struct ShareImageTests {

    private let author = Account(id: "1", username: "alice", acct: "alice")

    private func post(spoiler: String = "", sensitive: Bool = false) -> Status {
        Status(
            id: "s", url: URL(string: "https://example.test/@alice/1"), spoilerText: spoiler,
            sensitive: sensitive, account: author,
            mediaAttachments: [MediaAttachment(id: "m", type: .image)])
    }

    @Test("A plain post shows everything")
    func plain() {
        let disclosure = PostImageDisclosure.decide(
            for: post(), policy: .blur, spoilerRevealed: false, mediaRevealed: false)
        #expect(disclosure == PostImageDisclosure(showsBody: true, showsMedia: true))
        #expect(!disclosure.hidesSomething(in: post()))
    }

    @Test("A content warning hides the words and the picture until it is opened")
    func contentWarning() {
        let warned = post(spoiler: "spoilers")
        let closed = PostImageDisclosure.decide(
            for: warned, policy: .showAll, spoilerRevealed: false, mediaRevealed: true)
        #expect(closed == PostImageDisclosure(showsBody: false, showsMedia: false))
        #expect(closed.hidesSomething(in: warned))

        let opened = PostImageDisclosure.decide(
            for: warned, policy: .showAll, spoilerRevealed: true, mediaRevealed: false)
        #expect(opened == PostImageDisclosure(showsBody: true, showsMedia: true))
    }

    @Test("A sensitive picture stays covered unless uncovered or shown by policy")
    func sensitive() {
        let status = post(sensitive: true)
        #expect(
            !PostImageDisclosure.decide(
                for: status, policy: .blur, spoilerRevealed: false, mediaRevealed: false
            ).showsMedia)
        #expect(
            !PostImageDisclosure.decide(
                for: status, policy: .hideAll, spoilerRevealed: false, mediaRevealed: false
            ).showsMedia)
        #expect(
            PostImageDisclosure.decide(
                for: status, policy: .blur, spoilerRevealed: false, mediaRevealed: true
            ).showsMedia)
        #expect(
            PostImageDisclosure.decide(
                for: status, policy: .showAll, spoilerRevealed: false, mediaRevealed: false
            ).showsMedia)
    }

    @Test("What a row reveals is remembered for the share sheet, and closing it forgets")
    func registry() {
        let revealed = RevealedContent()
        #expect(!revealed.isSpoilerRevealed("s"))
        revealed.setSpoiler("s", revealed: true)
        #expect(revealed.isSpoilerRevealed("s"))
        revealed.setSpoiler("s", revealed: false)
        #expect(!revealed.isSpoilerRevealed("s"))
        revealed.revealMedia(["m"])
        #expect(revealed.isMediaRevealed(["x", "m"]))
        #expect(!revealed.isMediaRevealed(["x"]))
    }

    @Test("Poll results are shares of the votes, with the leader marked")
    func pollResults() {
        let poll = Poll(
            id: "p", votesCount: 4,
            options: [
                Poll.Option(title: "Tea", votesCount: 3),
                Poll.Option(title: "Coffee", votesCount: 1),
            ])
        let summary = PollResultsSummary(poll)
        #expect(summary.rows.map(\.share) == [0.75, 0.25])
        #expect(summary.rows.map(\.isLeading) == [true, false])
        #expect(summary.votes == 4)
    }

    @Test("A poll whose totals are hidden draws no bars and no leader")
    func hiddenTotals() {
        let poll = Poll(id: "p", options: [Poll.Option(title: "A"), Poll.Option(title: "B")])
        let summary = PollResultsSummary(poll)
        #expect(summary.rows.allSatisfy { $0.share == nil && !$0.isLeading })
    }

    @Test("The QR code is square and made of whole pixels")
    func qrCode() throws {
        let image = try #require(
            PostQRCode.image(for: URL(string: "https://example.test/@alice/1")!))
        #expect(image.width == image.height)
        #expect(image.width >= 96)
    }

    @Test("The rendered card becomes PNG bytes")
    func png() throws {
        let image = try #require(
            PostQRCode.image(for: URL(string: "https://example.test/@alice/1")!))
        let data = try #require(PostImageFile.pngData(image))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }
}
