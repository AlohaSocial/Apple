// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// The pure decision behind inserting a fetched page into a cached timeline.
///
/// Kept free of SwiftData so it can be tested exhaustively — the gap rules are
/// where a client of this kind most often goes quietly wrong (docs/08 §8).
public enum TimelineMerge {

    /// One row of a cached timeline, in display order.
    public struct Slot: Sendable, Hashable {
        public var statusID: String
        public var position: Int64
        public var isGapMarker: Bool

        public init(statusID: String, position: Int64, isGapMarker: Bool = false) {
            self.statusID = statusID
            self.position = position
            self.isGapMarker = isGapMarker
        }

        /// A gap's id names the boundary it sits at, so closing it is idempotent.
        public static func gap(below statusID: String, position: Int64) -> Slot {
            Slot(statusID: "gap:\(statusID)", position: position, isGapMarker: true)
        }
    }

    public struct Plan: Sendable, Hashable {
        /// The timeline as it should be after the merge, in order.
        public var slots: [Slot]
        /// Statuses to write to the shared store.
        public var insertedStatusIDs: [String]
        /// Gap markers to remove, because this page closed them.
        public var closedGapIDs: [String]
        /// Gap markers to add.
        public var openedGapIDs: [String]

        public var isEmpty: Bool {
            insertedStatusIDs.isEmpty && closedGapIDs.isEmpty && openedGapIDs.isEmpty
        }
    }

    public enum Direction: Sendable, Hashable {
        /// A refresh: `min_id` from the newest cached row.
        case newer
        /// Infinite scroll: `max_id` from the oldest cached row.
        case older
        /// A cold load, or a pull that replaces everything.
        case cold
        /// Filling a specific gap, which is closed only when the page proves
        /// the two ranges now touch.
        case fillingGap(id: String)
    }

    /// - Parameters:
    ///   - existing: the cached timeline, in display order.
    ///   - page: what the server just returned, in the server's order.
    ///   - pageWasFull: the **query** returned `limit` rows. Decided on what the
    ///     query returned, not on what survived filtering — counting filtered
    ///     rows out would make a filtered page look like the end of the list.
    public static func plan(
        existing: [Slot],
        page: [String],
        direction: Direction,
        pageWasFull: Bool
    ) -> Plan {
        guard !page.isEmpty else {
            // An empty page while filling a gap proves there is nothing between
            // the two ranges, so the gap closes.
            if case .fillingGap(let id) = direction {
                return Plan(
                    slots: existing.filter { $0.statusID != id },
                    insertedStatusIDs: [], closedGapIDs: [id], openedGapIDs: [])
            }
            return Plan(slots: existing, insertedStatusIDs: [], closedGapIDs: [], openedGapIDs: [])
        }

        switch direction {
        case .cold:
            let slots = numbered(page, from: 0)
            return Plan(
                slots: slots, insertedStatusIDs: page,
                closedGapIDs: existing.filter(\.isGapMarker).map(\.statusID),
                openedGapIDs: [])

        case .newer:
            return planNewer(existing: existing, page: page, pageWasFull: pageWasFull)

        case .older:
            return planOlder(existing: existing, page: page)

        case .fillingGap(let id):
            return planGapFill(existing: existing, page: page, gapID: id, pageWasFull: pageWasFull)
        }
    }

    // MARK: - Newer

    private static func planNewer(existing: [Slot], page: [String], pageWasFull: Bool) -> Plan {
        let known = Set(existing.map(\.statusID))
        let fresh = page.filter { !known.contains($0) }
        guard !fresh.isEmpty else {
            return Plan(slots: existing, insertedStatusIDs: [], closedGapIDs: [], openedGapIDs: [])
        }

        let topPosition = existing.first?.position ?? 0
        var slots = numbered(fresh, from: topPosition + Int64(fresh.count) + 1, descending: true)
        var opened: [String] = []

        // A full page from a min_id fetch means there may be more between what
        // arrived and what was cached. Insert a gap rather than joining two
        // ranges that may not touch.
        if pageWasFull, let anchor = fresh.last, !existing.isEmpty {
            let gap = Slot.gap(below: anchor, position: (slots.last?.position ?? 0) - 1)
            slots.append(gap)
            opened.append(gap.statusID)
        }

        return Plan(
            slots: slots + existing, insertedStatusIDs: fresh,
            closedGapIDs: [], openedGapIDs: opened)
    }

    // MARK: - Older

    private static func planOlder(existing: [Slot], page: [String]) -> Plan {
        let known = Set(existing.map(\.statusID))
        let fresh = page.filter { !known.contains($0) }
        guard !fresh.isEmpty else {
            return Plan(slots: existing, insertedStatusIDs: [], closedGapIDs: [], openedGapIDs: [])
        }

        let bottom = existing.last?.position ?? 0
        let appended = numbered(fresh, from: bottom - 1, descending: true)
        return Plan(
            slots: existing + appended, insertedStatusIDs: fresh,
            closedGapIDs: [], openedGapIDs: [])
    }

    // MARK: - Gap filling

    private static func planGapFill(
        existing: [Slot], page: [String], gapID: String, pageWasFull: Bool
    ) -> Plan {
        guard let gapIndex = existing.firstIndex(where: { $0.statusID == gapID }) else {
            return Plan(slots: existing, insertedStatusIDs: [], closedGapIDs: [], openedGapIDs: [])
        }

        let known = Set(existing.map(\.statusID))
        let fresh = page.filter { !known.contains($0) }

        let above = Array(existing[..<gapIndex])
        let below = Array(existing[(gapIndex + 1)...])

        // A page shorter than the limit proves the two ranges now touch, so the
        // gap closes. A full page means there is still more in between, so the
        // gap moves down rather than disappearing.
        let gapSurvives = pageWasFull && !fresh.isEmpty

        let upper = above.last?.position ?? 0
        let lower = below.first?.position ?? (upper - Int64(fresh.count) - 2)
        let span = max(1, upper - lower)
        let step = max(1, span / Int64(fresh.count + (gapSurvives ? 2 : 1)))

        var filled: [Slot] = []
        var cursor = upper
        for id in fresh {
            cursor -= step
            filled.append(Slot(statusID: id, position: cursor))
        }

        var opened: [String] = []
        if gapSurvives, let anchor = fresh.last {
            cursor -= step
            let gap = Slot.gap(below: anchor, position: cursor)
            filled.append(gap)
            opened.append(gap.statusID)
        }

        return Plan(
            slots: above + filled + below,
            insertedStatusIDs: fresh,
            closedGapIDs: [gapID],
            openedGapIDs: opened
        )
    }

    // MARK: - Helpers

    private static func numbered(
        _ ids: [String], from start: Int64, descending: Bool = true
    ) -> [Slot] {
        ids.enumerated().map { offset, id in
            Slot(statusID: id, position: descending ? start - Int64(offset) : start + Int64(offset))
        }
    }

    /// Removes a status from a timeline, which is what a delete over streaming
    /// or a 404 on refetch means.
    public static func removing(_ statusID: String, from slots: [Slot]) -> [Slot] {
        slots.filter { $0.statusID != statusID }
    }

    /// Whether the cached timeline is ordered and free of duplicates. Used by
    /// the tests and by a debug assertion after every merge.
    public static func isWellFormed(_ slots: [Slot]) -> Bool {
        var seen = Set<String>()
        var lastPosition: Int64?
        for slot in slots {
            if !seen.insert(slot.statusID).inserted { return false }
            if let last = lastPosition, slot.position >= last { return false }
            lastPosition = slot.position
        }
        return true
    }
}
