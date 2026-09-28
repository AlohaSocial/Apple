// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import SwiftData

@Model
public final class AccountRecord {
    #Unique<AccountRecord>([\.id])
    #Index<AccountRecord>([\.sortIndex])

    public var id: UUID = UUID()
    public var instanceHost: String = ""
    public var apiBaseString: String = ""
    public var handle: String = ""
    public var displayName: String = ""
    public var avatarURLString: String?
    public var headerURLString: String?
    public var serverAccountID: String = ""
    public var capabilitiesData: Data = Data()
    public var settingsData: Data = Data()
    /// The token was revoked. The account stays in the list, marked, with its
    /// cache intact, until the person removes it or signs in again (docs/02 §6).
    public var needsReauthentication: Bool = false
    public var sortIndex: Int = 0
    public var addedAt: Date = Date.distantPast

    public init(
        id: UUID = UUID(), instanceHost: String, apiBase: URL, handle: String,
        displayName: String, serverAccountID: String, capabilities: ServerCapabilities,
        settings: AccountSettings = AccountSettings(), sortIndex: Int = 0
    ) {
        self.id = id
        self.instanceHost = instanceHost
        self.apiBaseString = apiBase.absoluteString
        self.handle = handle
        self.displayName = displayName
        self.serverAccountID = serverAccountID
        self.capabilitiesData = (try? AlohaJSON.encoder.encode(capabilities)) ?? Data()
        self.settingsData = (try? AlohaJSON.encoder.encode(settings)) ?? Data()
        self.sortIndex = sortIndex
        self.addedAt = Date()
    }

    public var apiBase: URL {
        URL(string: apiBaseString) ?? URL(string: "https://invalid.invalid/")!
    }

    public var avatarURL: URL? { avatarURLString.flatMap(URL.init(string:)) }
    public var headerURL: URL? { headerURLString.flatMap(URL.init(string:)) }

    /// Blobs are versioned independently and a blob this build cannot read is
    /// discarded and refetched, never crashed on (docs/04 §5).
    public var capabilities: ServerCapabilities {
        get {
            (try? AlohaJSON.decoder.decode(ServerCapabilities.self, from: capabilitiesData))
                ?? .minimal(apiBase: apiBase)
        }
        set { capabilitiesData = (try? AlohaJSON.encoder.encode(newValue)) ?? capabilitiesData }
    }

    public var settings: AccountSettings {
        get {
            (try? AlohaJSON.decoder.decode(AccountSettings.self, from: settingsData))
                ?? AccountSettings()
        }
        set { settingsData = (try? AlohaJSON.encoder.encode(newValue)) ?? settingsData }
    }

    public var qualifiedHandle: String {
        handle.contains("@") ? "@\(handle)" : "@\(handle)@\(instanceHost)"
    }
}

@Model
public final class StatusRecord {
    #Unique<StatusRecord>([\.accountID, \.serverID])
    #Index<StatusRecord>([\.accountID, \.serverID], [\.accountID, \.createdAt])

    public var accountID: UUID = UUID()
    public var serverID: String = ""
    public var payload: Data = Data()
    public var createdAt: Date = Date.distantPast
    public var cachedAt: Date = Date.distantPast
    /// Decided once on insert and persisted, so a mode never reclassifies a
    /// whole page on scroll (docs/04 §3).
    public var contentKindRaw: String = ContentKind.text.rawValue
    /// Derived, for search and for the AI features' input.
    public var plainText: String = ""

    public init(accountID: UUID, status: Status, contentKind: ContentKind, plainText: String) {
        self.accountID = accountID
        self.serverID = status.id
        self.payload = (try? AlohaJSON.encoder.encode(status)) ?? Data()
        self.createdAt = status.createdAt
        self.cachedAt = Date()
        self.contentKindRaw = contentKind.rawValue
        self.plainText = plainText
    }

    public var status: Status? {
        try? AlohaJSON.decoder.decode(Status.self, from: payload)
    }

    public var contentKind: ContentKind {
        ContentKind(rawValue: contentKindRaw) ?? .text
    }

    public func update(status: Status, contentKind: ContentKind, plainText: String) {
        self.payload = (try? AlohaJSON.encoder.encode(status)) ?? payload
        self.createdAt = status.createdAt
        self.cachedAt = Date()
        self.contentKindRaw = contentKind.rawValue
        self.plainText = plainText
    }
}

/// A status appears in several timelines and is stored once; ordering is
/// per-timeline. Deleting one timeline's cache must not delete statuses another
/// still shows (docs/04 §3).
@Model
public final class TimelineEntry {
    #Unique<TimelineEntry>([\.accountID, \.timelineKey, \.statusServerID])
    #Index<TimelineEntry>([\.accountID, \.timelineKey, \.position])

    public var accountID: UUID = UUID()
    public var timelineKey: String = ""
    public var statusServerID: String = ""
    /// Assigned from a per-timeline descending counter rather than from
    /// `createdAt`, because boosts sort by boost time and the server's order is
    /// authoritative.
    public var position: Int64 = 0
    public var insertedAt: Date = Date.distantPast
    /// A hole between two fetched ranges. Rendered as "Load more"; never
    /// silently closed, because joining two disjoint ranges produces a timeline
    /// with invisible holes.
    public var isGapMarker: Bool = false

    public init(
        accountID: UUID, timelineKey: String, statusServerID: String,
        position: Int64, isGapMarker: Bool = false
    ) {
        self.accountID = accountID
        self.timelineKey = timelineKey
        self.statusServerID = statusServerID
        self.position = position
        self.insertedAt = Date()
        self.isGapMarker = isGapMarker
    }
}

@Model
public final class NotificationRecord {
    #Unique<NotificationRecord>([\.accountID, \.serverID])
    #Index<NotificationRecord>([\.accountID, \.createdAt])

    public var accountID: UUID = UUID()
    /// A v1 id, or a v2 `group_key`.
    public var serverID: String = ""
    public var isGroup: Bool = false
    public var kindRaw: String = ""
    public var createdAt: Date = Date.distantPast
    public var groupCount: Int = 1
    public var payload: Data = Data()
    public var statusServerID: String?
    public var dismissed: Bool = false
    /// Whether a local notification was already raised for this row. The raised
    /// set is persisted so a poll cannot announce the same mention twice.
    public var announced: Bool = false

    public init(
        accountID: UUID, serverID: String, isGroup: Bool, kind: NotificationKind,
        createdAt: Date, groupCount: Int, payload: Data, statusServerID: String?
    ) {
        self.accountID = accountID
        self.serverID = serverID
        self.isGroup = isGroup
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.groupCount = groupCount
        self.payload = payload
        self.statusServerID = statusServerID
    }

    public var kind: NotificationKind { NotificationKind(rawValue: kindRaw) ?? .unknownCase }
}

@Model
public final class DraftRecord {
    #Index<DraftRecord>([\.accountID, \.updatedAt])

    public var id: UUID = UUID()
    public var accountID: UUID = UUID()
    public var text: String = ""
    public var spoilerText: String = ""
    public var visibilityRaw: String = Visibility.public.rawValue
    public var sensitive: Bool = false
    public var language: String?
    public var inReplyToID: String?
    /// Already-uploaded ids, so re-opening a draft does not re-upload what is
    /// already on the server (docs/07 §5).
    public var uploadedMediaIDs: [String] = []
    public var localMediaPaths: [String] = []
    public var pollOptions: [String] = []
    public var pollExpiresIn: Int?
    public var pollMultiple: Bool = false
    public var scheduledAt: Date?
    /// Generated when the composer opened and regenerated only when content
    /// changes — what makes retry-on-timeout safe.
    public var idempotencyKey: String = UUID().uuidString
    public var queuedForSend: Bool = false
    public var lastSendError: String?
    public var updatedAt: Date = Date.distantPast
    /// Position in a thread being posted as a chain, so a failure part-way
    /// through can resume rather than re-post.
    public var threadIndex: Int = 0
    public var threadGroupID: UUID?

    public init(accountID: UUID, text: String = "") {
        self.accountID = accountID
        self.text = text
        self.updatedAt = Date()
    }

    public var visibility: Visibility {
        get { Visibility(rawValue: visibilityRaw) ?? .public }
        set { visibilityRaw = newValue.rawValue }
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && uploadedMediaIDs.isEmpty && localMediaPaths.isEmpty && pollOptions.isEmpty
    }
}

@Model
public final class MarkerRecord {
    #Unique<MarkerRecord>([\.accountID, \.timeline])

    public var accountID: UUID = UUID()
    public var timeline: String = ""
    public var lastReadID: String = ""
    public var updatedAt: Date = Date.distantPast

    public init(accountID: UUID, timeline: String, lastReadID: String) {
        self.accountID = accountID
        self.timeline = timeline
        self.lastReadID = lastReadID
        self.updatedAt = Date()
    }
}

@Model
public final class WatchPositionRecord {
    #Unique<WatchPositionRecord>([\.accountID, \.statusServerID])

    public var accountID: UUID = UUID()
    public var statusServerID: String = ""
    public var position: Double = 0
    public var duration: Double = 0
    public var updatedAt: Date = Date.distantPast

    public init(accountID: UUID, statusServerID: String, position: Double, duration: Double) {
        self.accountID = accountID
        self.statusServerID = statusServerID
        self.position = position
        self.duration = duration
        self.updatedAt = Date()
    }

    public var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }
}

@Model
public final class FilterRecord {
    #Unique<FilterRecord>([\.accountID, \.serverID])

    public var accountID: UUID = UUID()
    public var serverID: String = ""
    public var payload: Data = Data()
    public var expiresAt: Date?

    public init(accountID: UUID, filter: Filter) {
        self.accountID = accountID
        self.serverID = filter.id
        self.payload = (try? AlohaJSON.encoder.encode(filter)) ?? Data()
        self.expiresAt = filter.expiresAt
    }

    public var filter: Filter? { try? AlohaJSON.decoder.decode(Filter.self, from: payload) }
}

@Model
public final class RelationshipRecord {
    #Unique<RelationshipRecord>([\.accountID, \.targetID])

    public var accountID: UUID = UUID()
    public var targetID: String = ""
    public var payload: Data = Data()
    public var cachedAt: Date = Date.distantPast

    public init(accountID: UUID, relationship: Relationship) {
        self.accountID = accountID
        self.targetID = relationship.id
        self.payload = (try? AlohaJSON.encoder.encode(relationship)) ?? Data()
        self.cachedAt = Date()
    }

    public var relationship: Relationship? {
        try? AlohaJSON.decoder.decode(Relationship.self, from: payload)
    }
}
