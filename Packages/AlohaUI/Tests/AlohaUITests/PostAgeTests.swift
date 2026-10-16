// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaUI

@Suite struct PostAgeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aPostDatedInTheFutureReadsNow() {
        // Server clock ahead, or a round trip finishing after `created_at`:
        // "in 0s" claimed the post had not happened yet.
        #expect(PostAge.short(now.addingTimeInterval(4), now: now) == "now")
        #expect(PostAge.short(now.addingTimeInterval(600), now: now) == "now")
        #expect(PostAge.spoken(now.addingTimeInterval(4), now: now) == "now")
    }

    @Test func aPostFromSecondsAgoReadsNow() {
        #expect(PostAge.short(now.addingTimeInterval(-1), now: now) == "now")
        #expect(PostAge.short(now.addingTimeInterval(-59), now: now) == "now")
    }

    @Test func anOlderPostKeepsItsRelativeTime() {
        let short = PostAge.short(now.addingTimeInterval(-3600), now: now)
        #expect(short != "now")
        #expect(!short.isEmpty)
        #expect(PostAge.spoken(now.addingTimeInterval(-86_400), now: now) != "now")
    }

    @Test func aLiveAgeRedrawsAsOftenAsItsWordsChange() {
        // Minutes for the first hour, hours for the first day, then days:
        // last week's post is not redrawn every minute.
        #expect(PostAge.refreshInterval(for: now.addingTimeInterval(-30), now: now) == 60)
        #expect(PostAge.refreshInterval(for: now.addingTimeInterval(-3599), now: now) == 60)
        #expect(PostAge.refreshInterval(for: now.addingTimeInterval(-3600), now: now) == 3600)
        #expect(PostAge.refreshInterval(for: now.addingTimeInterval(-86_400), now: now) == 86_400)
        // A post dated ahead of the clock still ticks each minute.
        #expect(PostAge.refreshInterval(for: now.addingTimeInterval(120), now: now) == 60)
    }

    @Test func theAbsoluteTimeCarriesTheDateAndTheTime() {
        let absolute = PostAge.absolute(now)
        #expect(absolute.contains("2027"))
        #expect(absolute != PostAge.short(now, now: now))
    }

    @Test func webLinksOpenInTheAppUnlessTheReaderAskedOtherwise() throws {
        let page = try #require(URL(string: "https://example.test/article"))
        let plain = try #require(URL(string: "http://example.test/"))
        let mail = try #require(URL(string: "mailto:someone@example.test"))
        #expect(LinkOpening.prefersInApp(page, externally: false))
        #expect(LinkOpening.prefersInApp(plain, externally: false))
        #expect(!LinkOpening.prefersInApp(page, externally: true))
        // Nothing the in-app browser cannot show goes there.
        #expect(!LinkOpening.prefersInApp(mail, externally: false))
    }
}
