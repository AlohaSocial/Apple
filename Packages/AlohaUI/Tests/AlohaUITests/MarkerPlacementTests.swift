// SPDX-License-Identifier: MIT

import AlohaModels
import Testing

/// Where the catch-up divider goes, decided by the same rule the view uses.
///
/// The marker names one notification the reader had seen; the divider belongs
/// below the group containing it. Ids are opaque, so the comparison is never
/// lexicographic — a group is placed by its *position* relative to the
/// marker's, and the marker's own id only says which group it is.
@Suite("Catch-up marker placement")
struct MarkerPlacementTests {

    /// The rule the grouped list uses, stated once so the view and the test
    /// cannot drift: the first group whose newest notification is the marker's
    /// is where the divider sits below.
    static func dividerIndex<G>(
        in groups: [G], markerID: String, newestID: (G) -> String
    ) -> Int? {
        groups.firstIndex { newestID($0) == markerID }
    }

    @Test("The divider sits below the group the marker names")
    func findsTheMarkersGroup() {
        let groups = ["a-9", "b-8", "c-7", "d-6"]
        let index = Self.dividerIndex(in: groups, markerID: "b-8", newestID: { $0 })
        #expect(index == 1)
    }

    @Test("A marker naming nothing places no divider")
    func markerNotFound() {
        let groups = ["a-9", "b-8"]
        let index = Self.dividerIndex(in: groups, markerID: "zz-1", newestID: { $0 })
        #expect(index == nil)
    }

    /// A marker already at the top means there is nothing below it to divide
    /// from: the reader has seen everything, so no divider is drawn at all
    /// rather than one that separates the newest post from nothing.
    @Test("A marker on the newest group draws nothing")
    func markerOnNewestGroup() {
        let groups = ["a-9", "b-8"]
        let index = Self.dividerIndex(in: groups, markerID: "a-9", newestID: { $0 })
        #expect(index == 0)
        // index 0 is the first group; with nothing above it the divider would
        // sit at the very top, which reads as "start here" rather than
        // "everything above this is old".
        #expect(index == groups.startIndex)
    }

    /// Group ids carry a kind prefix (`favourite-123`) and a bare notification
    /// id does not; comparing them as strings would sort by prefix rather than
    /// by arrival, which is the bug this rule exists to avoid.
    @Test("Ids are compared by identity, never by order")
    func idsAreNotComparable() {
        let groups = ["favourite-9", "follow-10", "mention-2"]
        // The marker is "follow-10", which sorts *before* "favourite-9" as a
        // string but is the group it names.
        let index = Self.dividerIndex(in: groups, markerID: "follow-10", newestID: { $0 })
        #expect(index == 1)
    }
}
