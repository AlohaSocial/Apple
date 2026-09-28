// SPDX-License-Identifier: MIT

import AlohaNetwork
import AlohaStore
import Testing

@testable import AlohaUI

/// The four lines that decide what a refresh asks for.
///
/// They cost a visible bug once — a freshly built model with a warm cache asked
/// the server only for what was *newer*, got nothing, and left another source's
/// rows on screen under the wrong title. The fix was a one-word condition, and
/// nothing failed when it was wrong, so it is pinned here.
@Suite("Timeline refresh plan")
struct RefreshPlanTests {
    @Test("A model that has never fetched asks for the head, cache or no cache")
    func firstFetchIsCold() {
        // The case that broke: rows on screen from the cache, but nothing
        // fetched yet. "I have rows" is not "I have fetched".
        let withCache = TimelineModel.refreshPlan(hasFetchedBefore: false, newestRowID: "42")
        #expect(withCache.anchor == .cold)
        #expect(withCache.direction == .cold)

        let withoutCache = TimelineModel.refreshPlan(hasFetchedBefore: false, newestRowID: nil)
        #expect(withoutCache.anchor == .cold)
        #expect(withoutCache.direction == .cold)
    }

    @Test("Once it has fetched, it asks only for what is newer than the top row")
    func laterRefreshesAreIncremental() {
        let plan = TimelineModel.refreshPlan(hasFetchedBefore: true, newestRowID: "42")
        #expect(plan.anchor == .newerThan("42"))
        #expect(plan.direction == .newer)
    }

    @Test("A fetched-but-empty timeline goes cold rather than anchoring to nothing")
    func emptyAfterFetchIsCold() {
        // Everything filtered away, or a genuinely empty feed. There is no id
        // to be newer than, and asking for one would send `min_id=`.
        let plan = TimelineModel.refreshPlan(hasFetchedBefore: true, newestRowID: nil)
        #expect(plan.anchor == .cold)
        #expect(plan.direction == .cold)
    }

    @Test("The anchor and the merge direction never disagree")
    func anchorAndDirectionAgree() {
        // A cold anchor merged as `.newer` would append the head of the
        // timeline below the rows already held; a `.newerThan` anchor merged as
        // `.cold` would throw away everything below the new page. Neither is
        // reachable, and this is what says so.
        for hasFetched in [true, false] {
            for newest in ["42", nil] {
                let plan = TimelineModel.refreshPlan(
                    hasFetchedBefore: hasFetched, newestRowID: newest)
                switch plan.anchor {
                case .cold:
                    #expect(plan.direction == .cold)
                case .newerThan:
                    #expect(plan.direction == .newer)
                default:
                    Issue.record("a refresh should never page older: \(plan.anchor)")
                }
            }
        }
    }
}
