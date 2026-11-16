// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaUI

@Suite("The year in review as a story")
struct AnnualReportStoryTests {
    private let alice = Account(id: "a", username: "alice", acct: "alice")

    @Test("A quiet year still opens and closes, with nothing in between that it lacks")
    func quietYear() {
        let report = AnnualReport(year: 2025)
        #expect(AnnualReportStory.cards(for: report, in: nil) == [.opening, .closing])
    }

    @Test("A full year gets every card, in order, with at most five hashtags")
    func fullYear() {
        let tags = (1...7).map { AnnualHashtag(name: "tag\($0)", count: $0) }
        let report = AnnualReport(
            year: 2025,
            data: AnnualReportData(
                archetype: .oracle,
                timeSeries: [AnnualMonth(month: 3, statuses: 4, followers: 1)],
                topHashtags: tags,
                topStatuses: AnnualTopStatuses(byReblogs: "1", byFavourites: "1")))
        let wrapped = WrappedAnnualReports(
            annualReports: [report], statuses: [Status(id: "1", account: alice)])

        let cards = AnnualReportStory.cards(for: report, in: wrapped)
        #expect(cards.map(\.id) == ["opening", "numbers", "months", "hashtags", "best", "closing"])
        guard case .hashtags(let shown) = cards[3] else {
            Issue.record("The fourth card is not the hashtags")
            return
        }
        #expect(shown.map(\.name) == ["tag7", "tag6", "tag5", "tag4", "tag3"])
        // The same post was boosted and favourited most: shown once.
        guard case .bestPosts(let best) = cards[4] else {
            Issue.record("The fifth card is not the best posts")
            return
        }
        #expect(best.map(\.kind) == [.boosted])
    }

    @Test("A best post the wrapper did not send is left out rather than drawn empty")
    func missingBestPost() {
        let best = AnnualReportStory.bestPosts(
            AnnualTopStatuses(byReplies: "9"), in: WrappedAnnualReports())
        #expect(best.isEmpty)
    }

    @Test("A tap on the leading third goes back, mirrored right to left")
    func tapZones() {
        #expect(AnnualReportStory.tapGoesBack(atX: 50, width: 300, rightToLeft: false))
        #expect(!AnnualReportStory.tapGoesBack(atX: 150, width: 300, rightToLeft: false))
        #expect(!AnnualReportStory.tapGoesBack(atX: 50, width: 300, rightToLeft: true))
        #expect(AnnualReportStory.tapGoesBack(atX: 250, width: 300, rightToLeft: true))
        #expect(!AnnualReportStory.tapGoesBack(atX: 10, width: 0, rightToLeft: false))
    }

    @Test("Cards only advance on their own without Reduce Motion and VoiceOver")
    func autoAdvance() {
        #expect(AnnualReportStory.advancesAutomatically(reduceMotion: false, voiceOver: false))
        #expect(!AnnualReportStory.advancesAutomatically(reduceMotion: true, voiceOver: false))
        #expect(!AnnualReportStory.advancesAutomatically(reduceMotion: false, voiceOver: true))
    }
}
