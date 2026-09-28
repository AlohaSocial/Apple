// SPDX-License-Identifier: MIT

import AlohaHTML
import AlohaModels
import Foundation
import OSLog
import SwiftData

/// Every write to the store goes through here, on a background context.
/// Views never touch a `ModelContext`.
@ModelActor
public actor TimelineStore {
    private static let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "store")
    private static let parser = StatusHTMLParser()

    // MARK: - Reading

    public func slots(accountID: UUID, timelineKey: String) throws -> [TimelineMerge.Slot] {
        var descriptor = FetchDescriptor<TimelineEntry>(
            predicate: #Predicate {
                $0.accountID == accountID && $0.timelineKey == timelineKey
            },
            sortBy: [SortDescriptor(\.position, order: .reverse)]
        )
        descriptor.fetchLimit = CachePolicy.homeTimelineLimit
        return try modelContext.fetch(descriptor).map {
            TimelineMerge.Slot(
                statusID: $0.statusServerID, position: $0.position, isGapMarker: $0.isGapMarker)
        }
    }

    public func statuses(accountID: UUID, ids: [String]) throws -> [String: Status] {
        guard !ids.isEmpty else { return [:] }
        let wanted = Set(ids)
        let descriptor = FetchDescriptor<StatusRecord>(
            predicate: #Predicate {
                $0.accountID == accountID && wanted.contains($0.serverID)
            }
        )
        var result: [String: Status] = [:]
        for record in try modelContext.fetch(descriptor) {
            if let status = record.status { result[record.serverID] = status }
        }
        return result
    }

    /// The cached timeline in display order, statuses resolved, gap markers
    /// preserved as their own rows.
    public func cachedTimeline(
        accountID: UUID, timelineKey: String
    ) throws -> [TimelineRow] {
        let slots = try slots(accountID: accountID, timelineKey: timelineKey)
        let statusIDs = slots.filter { !$0.isGapMarker }.map(\.statusID)
        let resolved = try statuses(accountID: accountID, ids: statusIDs)

        return slots.compactMap { slot in
            if slot.isGapMarker { return .gap(id: slot.statusID) }
            guard let status = resolved[slot.statusID] else { return nil }
            return .status(status)
        }
    }

    // MARK: - Writing

    /// Applies a fetched page. Returns the resulting rows so the caller can
    /// render without a second read.
    @discardableResult
    public func apply(
        page: [Status],
        accountID: UUID,
        timelineKey: String,
        direction: TimelineMerge.Direction,
        pageWasFull: Bool
    ) throws -> [TimelineRow] {
        let existing = try slots(accountID: accountID, timelineKey: timelineKey)
        let plan = TimelineMerge.plan(
            existing: existing,
            page: page.map(\.id),
            direction: direction,
            pageWasFull: pageWasFull
        )

        // Statuses are stored once and shared; a timeline only points at them.
        for status in page where plan.insertedStatusIDs.contains(status.id) {
            try upsert(status: status, accountID: accountID)
        }
        // A status already cached may have been edited or had its counts move.
        for status in page where !plan.insertedStatusIDs.contains(status.id) {
            try upsert(status: status, accountID: accountID)
        }

        // Capped before the write rather than trimmed after it: a second
        // fetch with a `fetchOffset` does not see pending inserts the way the
        // offset implies, and would delete the rows just added.
        let kept = Array(plan.slots.prefix(CachePolicy.limit(forTimelineKey: timelineKey)))
        try replaceEntries(accountID: accountID, timelineKey: timelineKey, slots: kept)
        try modelContext.save()

        assert(TimelineMerge.isWellFormed(kept), "timeline merge produced a malformed order")

        let statusesByID = Dictionary(
            page.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let cached = try statuses(
            accountID: accountID,
            ids: plan.slots.filter { !$0.isGapMarker }.map(\.statusID))

        return kept.compactMap { slot in
            if slot.isGapMarker { return .gap(id: slot.statusID) }
            if let status = statusesByID[slot.statusID] ?? cached[slot.statusID] {
                return .status(status)
            }
            return nil
        }
    }

    public func upsert(status: Status, accountID: UUID) throws {
        let serverID = status.id
        let descriptor = FetchDescriptor<StatusRecord>(
            predicate: #Predicate { $0.accountID == accountID && $0.serverID == serverID }
        )
        let kind = ContentClassifier.classify(status)
        let plain = Self.parser.plainText(status.displayed.content)

        if let existing = try modelContext.fetch(descriptor).first {
            existing.update(status: status, contentKind: kind, plainText: plain)
        } else {
            modelContext.insert(
                StatusRecord(
                    accountID: accountID, status: status, contentKind: kind, plainText: plain))
        }
    }

    /// An optimistic action that the server then confirmed or refused.
    public func updateStatus(accountID: UUID, status: Status) throws {
        try upsert(status: status, accountID: accountID)
        try modelContext.save()
    }

    /// A delete over streaming, or a 404 on refetch: the status goes, and so
    /// does every timeline entry pointing at it.
    public func deleteStatus(accountID: UUID, serverID: String) throws {
        try modelContext.delete(
            model: StatusRecord.self,
            where: #Predicate { $0.accountID == accountID && $0.serverID == serverID })
        try modelContext.delete(
            model: TimelineEntry.self,
            where: #Predicate { $0.accountID == accountID && $0.statusServerID == serverID })
        try modelContext.save()
    }

    /// Diffs rather than deleting and re-inserting.
    ///
    /// A batch `delete(model:where:)` and an `insert` in the same save is not
    /// safe here: the batch delete is applied at save time and takes the rows
    /// just inserted with it, leaving the timeline empty. Diffing also avoids
    /// churning every row on a refresh that added three.
    private func replaceEntries(
        accountID: UUID, timelineKey: String, slots: [TimelineMerge.Slot]
    ) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<TimelineEntry>(
                predicate: #Predicate {
                    $0.accountID == accountID && $0.timelineKey == timelineKey
                }))

        var byID = Dictionary(
            existing.map { ($0.statusServerID, $0) }, uniquingKeysWith: { first, _ in first })

        for slot in slots {
            if let row = byID.removeValue(forKey: slot.statusID) {
                row.position = slot.position
                row.isGapMarker = slot.isGapMarker
            } else {
                modelContext.insert(
                    TimelineEntry(
                        accountID: accountID, timelineKey: timelineKey,
                        statusServerID: slot.statusID, position: slot.position,
                        isGapMarker: slot.isGapMarker))
            }
        }

        // Whatever the new order does not mention is no longer in this timeline
        // — a closed gap, or a row trimmed off the end.
        for orphan in byID.values { modelContext.delete(orphan) }
    }

    // MARK: - Sweeping

    /// Budgeted so it cannot stall a launch (docs/04 §4).
    public func sweep(now: Date = Date()) throws {
        let orphanCutoff = now.addingTimeInterval(-CachePolicy.orphanStatusLifetime)
        let referenced = Set(
            try modelContext.fetch(FetchDescriptor<TimelineEntry>()).map(\.statusServerID))

        var descriptor = FetchDescriptor<StatusRecord>(
            predicate: #Predicate { $0.cachedAt < orphanCutoff })
        descriptor.fetchLimit = CachePolicy.maximumDeletionsPerPass

        var deletions = 0
        for record in try modelContext.fetch(descriptor) where !referenced.contains(record.serverID)
        {
            modelContext.delete(record)
            deletions += 1
        }

        let relationshipCutoff = now.addingTimeInterval(-CachePolicy.relationshipLifetime)
        try modelContext.delete(
            model: RelationshipRecord.self, where: #Predicate { $0.cachedAt < relationshipCutoff })

        let watchCutoff = now.addingTimeInterval(-CachePolicy.watchPositionLifetime)
        try modelContext.delete(
            model: WatchPositionRecord.self, where: #Predicate { $0.updatedAt < watchCutoff })

        try modelContext.save()
        Self.logger.debug("sweep removed \(deletions, privacy: .public) orphaned statuses")
    }

    /// Everything by one author, gone from every timeline at once. Blocking
    /// somebody and still seeing them until the next refresh is not blocking.
    public func removeEverything(fromAccount authorID: String, accountID: UUID) throws {
        let records = try modelContext.fetch(
            FetchDescriptor<StatusRecord>(predicate: #Predicate { $0.accountID == accountID }))

        var removed: [String] = []
        for record in records {
            guard let status = record.status else { continue }
            if status.account.id == authorID || status.displayed.account.id == authorID {
                removed.append(record.serverID)
                modelContext.delete(record)
            }
        }

        let gone = Set(removed)
        let entries = try modelContext.fetch(
            FetchDescriptor<TimelineEntry>(predicate: #Predicate { $0.accountID == accountID }))
        for entry in entries where gone.contains(entry.statusServerID) {
            modelContext.delete(entry)
        }

        try modelContext.save()
    }

    /// Removing an account takes everything of that account's with it —
    /// immediately and completely (docs/11 §2).
    public func deleteEverything(forAccount accountID: UUID) throws {
        try modelContext.delete(
            model: TimelineEntry.self, where: #Predicate { $0.accountID == accountID })
        try modelContext.delete(
            model: StatusRecord.self, where: #Predicate { $0.accountID == accountID })
        try modelContext.delete(
            model: NotificationRecord.self, where: #Predicate { $0.accountID == accountID })
        try modelContext.delete(
            model: DraftRecord.self, where: #Predicate { $0.accountID == accountID })
        try modelContext.delete(
            model: MarkerRecord.self, where: #Predicate { $0.accountID == accountID })
        try modelContext.delete(
            model: WatchPositionRecord.self, where: #Predicate { $0.accountID == accountID })
        try modelContext.delete(
            model: FilterRecord.self, where: #Predicate { $0.accountID == accountID })
        try modelContext.delete(
            model: RelationshipRecord.self, where: #Predicate { $0.accountID == accountID })
        try modelContext.delete(model: AccountRecord.self, where: #Predicate { $0.id == accountID })
        try modelContext.save()
    }
}

/// What a timeline hands a view: a post, or a hole to fill.
public enum TimelineRow: Sendable, Hashable, Identifiable {
    case status(Status)
    case gap(id: String)

    public var id: String {
        switch self {
        case .status(let status): status.id
        case .gap(let id): id
        }
    }

    public var status: Status? {
        if case .status(let status) = self { return status }
        return nil
    }
}
