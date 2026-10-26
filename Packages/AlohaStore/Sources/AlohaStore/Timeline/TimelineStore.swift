// SPDX-License-Identifier: MIT

import AlohaHTML
import AlohaModels
import Foundation
import OSLog
import SwiftData

public struct TimelineStatusUpdate: Sendable {
    public static let notification = Notification.Name("aloha.timelineStatusUpdate")
    public let accountID: UUID
    public let status: Status
    public init(accountID: UUID, status: Status) {
        self.accountID = accountID
        self.status = status
    }
}

/// Every write to the store goes through here, on a background context.
/// Views never touch a `ModelContext`.
@ModelActor
public actor TimelineStore {
    private static let logger = Logger(subsystem: "social.aloha.app", category: "store")
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

    /// The newest few posts of a cached timeline, for a surface that shows
    /// only those — a widget, which has a tight memory budget and no use for
    /// the other four hundred and ninety.
    public func latestStatuses(
        accountID: UUID, timelineKey: String, limit: Int
    ) throws -> [Status] {
        guard limit > 0 else { return [] }
        var descriptor = FetchDescriptor<TimelineEntry>(
            predicate: #Predicate {
                $0.accountID == accountID && $0.timelineKey == timelineKey && !$0.isGapMarker
            },
            sortBy: [SortDescriptor(\.position, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let ids = try modelContext.fetch(descriptor).map(\.statusServerID)
        let resolved = try statuses(accountID: accountID, ids: ids)
        return ids.compactMap { resolved[$0] }
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
        NotificationCenter.default.post(
            name: TimelineStatusUpdate.notification,
            object: TimelineStatusUpdate(accountID: accountID, status: status.displayed))
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
    ///
    /// In order: timelines nobody has added to for a while go, notifications
    /// past the limit go, and then the statuses nothing points at any more.
    /// Each step only ever shrinks what the next one has to keep.
    public func sweep(
        now: Date = Date(), maximumDeletions: Int = CachePolicy.maximumDeletionsPerPass
    ) throws {
        var entries = FetchDescriptor<TimelineEntry>()
        entries.propertiesToFetch = [
            \.accountID, \.timelineKey, \.statusServerID, \.insertedAt, \.isGapMarker,
        ]
        let (droppedTimelines, keptEntries) = try sweepTimelines(
            try modelContext.fetch(entries), now: now)
        let droppedNotifications = try trimNotifications()
        let droppedStatuses = try sweepStatuses(
            keptEntries: keptEntries, now: now, budget: maximumDeletions)

        let relationshipCutoff = now.addingTimeInterval(-CachePolicy.relationshipLifetime)
        try modelContext.delete(
            model: RelationshipRecord.self, where: #Predicate { $0.cachedAt < relationshipCutoff })

        let watchCutoff = now.addingTimeInterval(-CachePolicy.watchPositionLifetime)
        try modelContext.delete(
            model: WatchPositionRecord.self, where: #Predicate { $0.updatedAt < watchCutoff })

        try modelContext.save()
        Self.logger.debug(
            """
            sweep removed \(droppedTimelines, privacy: .public) timelines, \
            \(droppedNotifications, privacy: .public) notifications, \
            \(droppedStatuses, privacy: .public) orphaned statuses
            """)
    }

    /// Drops the cached copy of every timeline that may age — a profile, a
    /// tag, a list — once nothing has been added to it for
    /// `otherTimelineLifetime`, and beyond the `otherTimelineCount` most
    /// recently added to per account. Each holds up to two hundred rows, and
    /// one is made for every profile and tag somebody ever opened; kept
    /// forever, they were most of the store. Opening one again is a cold
    /// load, which opening one does anyway.
    ///
    /// A timeline's newest `insertedAt` is when it last gained a post. A
    /// refresh that found nothing new does not count, which is the right
    /// answer for a profile that has gone quiet.
    ///
    /// Returns how many timelines went, and the entries that stay.
    private func sweepTimelines(
        _ entries: [TimelineEntry], now: Date
    ) throws -> (dropped: Int, kept: [TimelineEntry]) {
        struct Key: Hashable {
            let accountID: UUID
            let timelineKey: String
        }
        let byTimeline = Dictionary(grouping: entries) {
            Key(accountID: $0.accountID, timelineKey: $0.timelineKey)
        }
        let ageing = byTimeline.compactMap { key, rows in
            CachePolicy.ages(timelineKey: key.timelineKey)
                ? (key: key, lastAdded: rows.map(\.insertedAt).max() ?? .distantPast) : nil
        }

        let cutoff = now.addingTimeInterval(-CachePolicy.otherTimelineLifetime)
        var dropped = Set<Key>()
        for (_, timelines) in Dictionary(grouping: ageing, by: \.key.accountID) {
            let newestFirst = timelines.sorted { $0.lastAdded > $1.lastAdded }
            for (index, timeline) in newestFirst.enumerated()
            where index >= CachePolicy.otherTimelineCount || timeline.lastAdded < cutoff {
                dropped.insert(timeline.key)
            }
        }

        // One row at a time rather than a batch delete per timeline: a batch
        // delete lands only at save, and the statuses these rows point at are
        // to be freed in this same pass.
        var kept: [TimelineEntry] = []
        for (key, rows) in byTimeline {
            if dropped.contains(key) {
                for row in rows { modelContext.delete(row) }
            } else {
                kept.append(contentsOf: rows)
            }
        }
        return (dropped.count, kept)
    }

    /// Keeps each account's newest `notificationLimit` notifications. What
    /// is older has long been announced and scrolled past, and a poll only
    /// ever asks for the newest forty, so nothing trimmed comes back as news.
    private func trimNotifications() throws -> Int {
        var trimmed = 0
        for accountID in try modelContext.fetch(FetchDescriptor<AccountRecord>()).map(\.id) {
            var descriptor = FetchDescriptor<NotificationRecord>(
                predicate: #Predicate { $0.accountID == accountID },
                sortBy: [
                    SortDescriptor(\.createdAt, order: .reverse), SortDescriptor(\.serverID),
                ])
            descriptor.fetchOffset = CachePolicy.notificationLimit
            descriptor.propertiesToFetch = [\.createdAt]
            for record in try modelContext.fetch(descriptor) {
                modelContext.delete(record)
                trimmed += 1
            }
        }
        return trimmed
    }

    /// Statuses cached long ago that no timeline or notification of their
    /// account points at.
    ///
    /// Read oldest first, and as many as there are referenced statuses plus
    /// the deletion budget: at most that many of them can be ones to keep,
    /// so every pass deletes either its whole budget or every orphan there
    /// is. An unsorted read capped at the budget alone could return the same
    /// still-referenced rows on every pass and delete nothing, ever.
    private func sweepStatuses(
        keptEntries: [TimelineEntry], now: Date, budget: Int
    ) throws -> Int {
        struct Reference: Hashable {
            let accountID: UUID
            let serverID: String
        }
        // Per account: two accounts on one server share ids, and each keeps
        // its own copy of a post.
        var referenced = Set<Reference>()
        for entry in keptEntries where !entry.isGapMarker {
            referenced.insert(Reference(accountID: entry.accountID, serverID: entry.statusServerID))
        }
        var notifications = FetchDescriptor<NotificationRecord>(
            predicate: #Predicate { $0.statusServerID != nil })
        notifications.propertiesToFetch = [\.accountID, \.statusServerID]
        for record in try modelContext.fetch(notifications) {
            guard let serverID = record.statusServerID else { continue }
            referenced.insert(Reference(accountID: record.accountID, serverID: serverID))
        }

        let orphanCutoff = now.addingTimeInterval(-CachePolicy.orphanStatusLifetime)
        var descriptor = FetchDescriptor<StatusRecord>(
            predicate: #Predicate { $0.cachedAt < orphanCutoff },
            sortBy: [SortDescriptor(\.cachedAt), SortDescriptor(\.serverID)])
        descriptor.fetchLimit = referenced.count + budget
        descriptor.propertiesToFetch = [\.accountID, \.serverID]

        var deletions = 0
        for record in try modelContext.fetch(descriptor) {
            guard deletions < budget else { break }
            let reference = Reference(accountID: record.accountID, serverID: record.serverID)
            guard !referenced.contains(reference) else { continue }
            modelContext.delete(record)
            deletions += 1
        }
        return deletions
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
    /// A "You're caught up" divider placed below the given status ID.
    case caughtUpDivider(after: String)

    public var id: String {
        switch self {
        case .status(let status): status.id
        case .gap(let id): id
        case .caughtUpDivider(let after): "caughtUp-\(after)"
        }
    }

    public var status: Status? {
        if case .status(let status) = self { return status }
        return nil
    }
}
