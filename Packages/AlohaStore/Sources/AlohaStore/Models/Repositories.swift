// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import SwiftData

/// Drafts, markers, watch positions, filters and notifications.
@ModelActor
public actor SupportStore {

    // MARK: - Markers

    /// **A marker never moves backwards.** The server enforces it and so does
    /// this, so a device that is behind cannot un-read what another has read
    /// (docs/08 §7).
    public func advanceMarker(accountID: UUID, timeline: String, to id: String) throws -> Bool {
        let descriptor = FetchDescriptor<MarkerRecord>(
            predicate: #Predicate { $0.accountID == accountID && $0.timeline == timeline })

        if let existing = try modelContext.fetch(descriptor).first {
            // Ids are opaque strings but are lexicographically ordered within a
            // server when zero-padded to equal length, so compare on length
            // first — which is what makes "1000" newer than "999".
            guard Self.isNewer(id, than: existing.lastReadID) else { return false }
            existing.lastReadID = id
            existing.updatedAt = Date()
        } else {
            modelContext.insert(
                MarkerRecord(accountID: accountID, timeline: timeline, lastReadID: id))
        }
        try modelContext.save()
        return true
    }

    public func marker(accountID: UUID, timeline: String) throws -> String? {
        try modelContext.fetch(
            FetchDescriptor<MarkerRecord>(
                predicate: #Predicate { $0.accountID == accountID && $0.timeline == timeline })
        ).first?.lastReadID
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        if candidate.count != current.count { return candidate.count > current.count }
        return candidate > current
    }

    // MARK: - Watch positions

    public func recordWatchPosition(
        accountID: UUID, statusID: String, position: Double, duration: Double
    ) throws {
        // Past 95 % the server forgets the position rather than bookmarking the
        // credits; the client mirrors that and clears its own row too.
        if WatchPositionRules.isComplete(position: position, duration: duration) {
            try modelContext.delete(
                model: WatchPositionRecord.self,
                where: #Predicate { $0.accountID == accountID && $0.statusServerID == statusID })
            try modelContext.save()
            return
        }

        let descriptor = FetchDescriptor<WatchPositionRecord>(
            predicate: #Predicate { $0.accountID == accountID && $0.statusServerID == statusID })

        if let existing = try modelContext.fetch(descriptor).first {
            existing.position = position
            existing.duration = duration
            existing.updatedAt = Date()
        } else {
            modelContext.insert(
                WatchPositionRecord(
                    accountID: accountID, statusServerID: statusID,
                    position: position, duration: duration))
        }
        try modelContext.save()
    }

    public func watchPosition(accountID: UUID, statusID: String) throws -> Double? {
        try modelContext.fetch(
            FetchDescriptor<WatchPositionRecord>(
                predicate: #Predicate { $0.accountID == accountID && $0.statusServerID == statusID }
            )
        ).first?.position
    }

    /// Everything this account has watched, as the fraction each video has
    /// got through. Read for the progress bar on a card: the shelf above it
    /// comes from the server, but a card should not need a round trip to
    /// admit it was already started.
    public func watchFractions(accountID: UUID) throws -> [String: Double] {
        let records = try modelContext.fetch(
            FetchDescriptor<WatchPositionRecord>(
                predicate: #Predicate { $0.accountID == accountID }))
        var fractions: [String: Double] = [:]
        for record in records where record.duration > 0 {
            fractions[record.statusServerID] = min(max(record.position / record.duration, 0), 1)
        }
        return fractions
    }

    // MARK: - Filters

    public func replaceFilters(_ filters: [Filter], accountID: UUID) throws {
        try modelContext.delete(
            model: FilterRecord.self, where: #Predicate { $0.accountID == accountID })
        for filter in filters {
            modelContext.insert(FilterRecord(accountID: accountID, filter: filter))
        }
        try modelContext.save()
    }

    public func activeFilters(accountID: UUID, now: Date = Date()) throws -> [Filter] {
        try modelContext.fetch(
            FetchDescriptor<FilterRecord>(predicate: #Predicate { $0.accountID == accountID })
        )
        .compactMap(\.filter)
        // An expired filter stops hiding without a refetch.
        .filter { !$0.isExpired(at: now) }
    }

    // MARK: - Drafts

    public func drafts(accountID: UUID) throws -> [DraftSnapshot] {
        try modelContext.fetch(
            FetchDescriptor<DraftRecord>(
                predicate: #Predicate { $0.accountID == accountID },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        ).map(DraftSnapshot.init)
    }

    @discardableResult
    public func saveDraft(_ snapshot: DraftSnapshot) throws -> UUID {
        let id = snapshot.id
        let descriptor = FetchDescriptor<DraftRecord>(predicate: #Predicate { $0.id == id })

        let record: DraftRecord
        if let existing = try modelContext.fetch(descriptor).first {
            record = existing
        } else {
            record = DraftRecord(accountID: snapshot.accountID)
            record.id = snapshot.id
            record.idempotencyKey = snapshot.idempotencyKey
            modelContext.insert(record)
        }

        record.text = snapshot.text
        record.spoilerText = snapshot.spoilerText
        record.visibility = snapshot.visibility
        record.sensitive = snapshot.sensitive
        record.language = snapshot.language
        record.inReplyToID = snapshot.inReplyToID
        record.uploadedMediaIDs = snapshot.uploadedMediaIDs
        record.localMediaPaths = snapshot.localMediaPaths
        record.pollOptions = snapshot.pollOptions
        record.pollExpiresIn = snapshot.pollExpiresIn
        record.pollMultiple = snapshot.pollMultiple
        record.scheduledAt = snapshot.scheduledAt
        record.queuedForSend = snapshot.queuedForSend
        record.idempotencyKey = snapshot.idempotencyKey
        record.threadIndex = snapshot.threadIndex
        record.threadGroupID = snapshot.threadGroupID
        record.quotedID = snapshot.quotedID
        record.quotePolicy = snapshot.quotePolicy
        record.threadSegments = snapshot.threadSegments
        record.lastSendError = snapshot.lastSendError
        record.threadPosition = snapshot.threadPosition
        record.replyPolicy = snapshot.replyPolicy
        record.marksAsAIGenerated = snapshot.marksAsAIGenerated
        record.placeID = snapshot.placeID
        record.placeName = snapshot.placeName
        record.placeCountry = snapshot.placeCountry
        record.postAs = snapshot.postAs
        record.cardBackgroundID = snapshot.cardBackgroundID
        record.videoTitle = snapshot.videoTitle
        record.videoCategory = snapshot.videoCategory
        record.videoLicence = snapshot.videoLicence
        record.updatedAt = Date()

        try modelContext.save()
        return record.id
    }

    public func deleteDraft(id: UUID) throws {
        try modelContext.delete(model: DraftRecord.self, where: #Predicate { $0.id == id })
        try modelContext.save()
    }

    /// Takes a draft off the send queue and says why, so it waits in Drafts
    /// with everything intact rather than being retried forever: what the
    /// server refused once it will refuse again (docs/07 §7).
    public func markSendFailed(id: UUID, message: String) throws {
        let descriptor = FetchDescriptor<DraftRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try modelContext.fetch(descriptor).first else { return }
        record.queuedForSend = false
        record.lastSendError = message
        try modelContext.save()
    }

    /// The send queue, in the order it must drain.
    public func queuedDrafts(accountID: UUID) throws -> [DraftSnapshot] {
        try modelContext.fetch(
            FetchDescriptor<DraftRecord>(
                predicate: #Predicate { $0.accountID == accountID && $0.queuedForSend },
                sortBy: [SortDescriptor(\.threadIndex), SortDescriptor(\.updatedAt)])
        ).map(DraftSnapshot.init)
    }

    // MARK: - Notifications

    public func storeNotifications(
        _ notifications: [StoredNotification], accountID: UUID
    ) throws -> [StoredNotification] {
        var newlyArrived: [StoredNotification] = []

        for notification in notifications {
            let serverID = notification.serverID
            let descriptor = FetchDescriptor<NotificationRecord>(
                predicate: #Predicate { $0.accountID == accountID && $0.serverID == serverID })

            if let existing = try modelContext.fetch(descriptor).first {
                // A group that grew is the same group: update in place so the
                // local notification is replaced rather than duplicated.
                if existing.groupCount != notification.groupCount {
                    existing.groupCount = notification.groupCount
                    existing.payload = notification.payload
                    existing.announced = false
                    newlyArrived.append(notification)
                }
            } else {
                modelContext.insert(
                    NotificationRecord(
                        accountID: accountID, serverID: notification.serverID,
                        isGroup: notification.isGroup, kind: notification.kind,
                        createdAt: notification.createdAt, groupCount: notification.groupCount,
                        payload: notification.payload, statusServerID: notification.statusServerID))
                newlyArrived.append(notification)
            }
        }

        try modelContext.save()
        return newlyArrived
    }

    /// A notification is announced at most once per server id; the raised set is
    /// persisted so a poll cannot say the same thing twice (docs/08 §5).
    public func markAnnounced(accountID: UUID, serverIDs: [String]) throws {
        let wanted = Set(serverIDs)
        let descriptor = FetchDescriptor<NotificationRecord>(
            predicate: #Predicate { $0.accountID == accountID && wanted.contains($0.serverID) })
        for record in try modelContext.fetch(descriptor) { record.announced = true }
        try modelContext.save()
    }

    public func unannouncedNotifications(accountID: UUID) throws -> [StoredNotification] {
        try modelContext.fetch(
            FetchDescriptor<NotificationRecord>(
                predicate: #Predicate { $0.accountID == accountID && !$0.announced },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        ).map(StoredNotification.init)
    }
}

public struct DraftSnapshot: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var accountID: UUID
    public var text: String
    public var spoilerText: String
    public var visibility: Visibility
    public var sensitive: Bool
    public var language: String?
    public var inReplyToID: String?
    public var uploadedMediaIDs: [String]
    public var localMediaPaths: [String]
    public var pollOptions: [String]
    public var pollExpiresIn: Int?
    public var pollMultiple: Bool
    public var scheduledAt: Date?
    public var idempotencyKey: String
    public var queuedForSend: Bool
    public var threadIndex: Int
    public var threadGroupID: UUID?
    public var quotedID: String?
    public var quotePolicy: String?
    public var threadSegments: [String]
    /// Why the send queue gave up on this draft, shown in Drafts.
    public var lastSendError: String?
    public var updatedAt: Date
    /// How many posts of this thread are already out; see `DraftRecord`.
    public var threadPosition = 0
    // The rest of what the composer sends; see `DraftRecord`.
    public var replyPolicy: String?
    public var marksAsAIGenerated = false
    public var placeID: String?
    public var placeName: String?
    public var placeCountry: String?
    public var postAs: String?
    public var cardBackgroundID: String?
    public var videoTitle: String?
    public var videoCategory: String?
    public var videoLicence: String?

    /// The key the post at `position` in this thread goes out with: the
    /// draft's own for the first, and one derived from it for each segment.
    /// Derived rather than random, so a segment whose first attempt landed
    /// unseen is recognised by the server when the queue sends it again.
    public func idempotencyKey(forPosition position: Int) -> String {
        position == 0 ? idempotencyKey : "\(idempotencyKey)-\(position)"
    }

    /// The same draft once `posted` posts of its thread are out, the last of
    /// them `lastPostedID`: the next segment becomes the text, replying to
    /// what went out. What belonged to the first post — media, poll, quote,
    /// schedule, place, card, video — has gone out with it.
    public func resuming(afterPosted posted: Int, lastPostedID: String) -> DraftSnapshot {
        var rest = self
        rest.text = threadSegments.first ?? ""
        rest.threadSegments = Array(threadSegments.dropFirst())
        rest.threadPosition = posted
        rest.inReplyToID = lastPostedID
        rest.uploadedMediaIDs = []
        rest.localMediaPaths = []
        rest.pollOptions = []
        rest.pollExpiresIn = nil
        rest.quotedID = nil
        rest.quotePolicy = nil
        rest.scheduledAt = nil
        rest.replyPolicy = nil
        rest.marksAsAIGenerated = false
        rest.placeID = nil
        rest.placeName = nil
        rest.placeCountry = nil
        rest.cardBackgroundID = nil
        rest.videoTitle = nil
        rest.videoCategory = nil
        rest.videoLicence = nil
        return rest
    }

    public init(
        id: UUID = UUID(), accountID: UUID, text: String = "", spoilerText: String = "",
        visibility: Visibility = .public, sensitive: Bool = false, language: String? = nil,
        inReplyToID: String? = nil, uploadedMediaIDs: [String] = [], localMediaPaths: [String] = [],
        pollOptions: [String] = [], pollExpiresIn: Int? = nil, pollMultiple: Bool = false,
        scheduledAt: Date? = nil, idempotencyKey: String = UUID().uuidString,
        queuedForSend: Bool = false, threadIndex: Int = 0, threadGroupID: UUID? = nil,
        quotedID: String? = nil, quotePolicy: String? = nil, threadSegments: [String] = [],
        lastSendError: String? = nil, updatedAt: Date = Date()
    ) {
        self.id = id
        self.accountID = accountID
        self.text = text
        self.spoilerText = spoilerText
        self.visibility = visibility
        self.sensitive = sensitive
        self.language = language
        self.inReplyToID = inReplyToID
        self.uploadedMediaIDs = uploadedMediaIDs
        self.localMediaPaths = localMediaPaths
        self.pollOptions = pollOptions
        self.pollExpiresIn = pollExpiresIn
        self.pollMultiple = pollMultiple
        self.scheduledAt = scheduledAt
        self.idempotencyKey = idempotencyKey
        self.queuedForSend = queuedForSend
        self.threadIndex = threadIndex
        self.threadGroupID = threadGroupID
        self.quotedID = quotedID
        self.quotePolicy = quotePolicy
        self.threadSegments = threadSegments
        self.lastSendError = lastSendError
        self.updatedAt = updatedAt
    }

    init(_ record: DraftRecord) {
        self.init(
            id: record.id, accountID: record.accountID, text: record.text,
            spoilerText: record.spoilerText, visibility: record.visibility,
            sensitive: record.sensitive, language: record.language,
            inReplyToID: record.inReplyToID, uploadedMediaIDs: record.uploadedMediaIDs,
            localMediaPaths: record.localMediaPaths, pollOptions: record.pollOptions,
            pollExpiresIn: record.pollExpiresIn, pollMultiple: record.pollMultiple,
            scheduledAt: record.scheduledAt, idempotencyKey: record.idempotencyKey,
            queuedForSend: record.queuedForSend, threadIndex: record.threadIndex,
            threadGroupID: record.threadGroupID, quotedID: record.quotedID,
            quotePolicy: record.quotePolicy, threadSegments: record.threadSegments,
            lastSendError: record.lastSendError, updatedAt: record.updatedAt)
        threadPosition = record.threadPosition
        replyPolicy = record.replyPolicy
        marksAsAIGenerated = record.marksAsAIGenerated
        placeID = record.placeID
        placeName = record.placeName
        placeCountry = record.placeCountry
        postAs = record.postAs
        cardBackgroundID = record.cardBackgroundID
        videoTitle = record.videoTitle
        videoCategory = record.videoCategory
        videoLicence = record.videoLicence
    }

    /// A quote with nothing typed is still a post: the quoted card is the
    /// content.
    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && uploadedMediaIDs.isEmpty && localMediaPaths.isEmpty && pollOptions.isEmpty
            && quotedID == nil
    }
}

public struct StoredNotification: Sendable, Hashable, Identifiable {
    public var serverID: String
    public var isGroup: Bool
    public var kind: NotificationKind
    public var createdAt: Date
    public var groupCount: Int
    public var payload: Data
    public var statusServerID: String?
    public var announced: Bool

    public var id: String { serverID }

    public init(
        serverID: String, isGroup: Bool, kind: NotificationKind, createdAt: Date,
        groupCount: Int, payload: Data, statusServerID: String?, announced: Bool = false
    ) {
        self.serverID = serverID
        self.isGroup = isGroup
        self.kind = kind
        self.createdAt = createdAt
        self.groupCount = groupCount
        self.payload = payload
        self.statusServerID = statusServerID
        self.announced = announced
    }

    init(_ record: NotificationRecord) {
        self.init(
            serverID: record.serverID, isGroup: record.isGroup, kind: record.kind,
            createdAt: record.createdAt, groupCount: record.groupCount, payload: record.payload,
            statusServerID: record.statusServerID, announced: record.announced)
    }
}
