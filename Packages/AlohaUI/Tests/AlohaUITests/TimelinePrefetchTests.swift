// SPDX-License-Identifier: MIT
import Testing

@testable import AlohaUI

@Suite("Timeline page buffer")
@MainActor
struct TimelinePrefetchTests {
    @Test("The next page starts before the reader reaches the last post")
    func aheadOfEnd() {
        let ids = (0..<20).map(String.init)
        #expect(!TimelineModel.shouldPrefetchOlder(visibleID: "11", loadedIDs: ids))
        #expect(TimelineModel.shouldPrefetchOlder(visibleID: "12", loadedIDs: ids))
        #expect(TimelineModel.shouldPrefetchOlder(visibleID: "19", loadedIDs: ids))
    }

    @Test("Unknown and empty timelines do not trigger page requests")
    func noSpuriousRequests() {
        #expect(!TimelineModel.shouldPrefetchOlder(visibleID: "missing", loadedIDs: ["first"]))
        #expect(!TimelineModel.shouldPrefetchOlder(visibleID: "first", loadedIDs: []))
    }
}
