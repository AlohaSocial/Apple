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
}
