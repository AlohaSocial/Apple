// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import SwiftData
import Testing

@testable import AlohaStore

private func makeStore() -> (TimelineStore, SupportStore, AccountStore, UUID) {
    let container = StoreContainer.make(inMemory: true)
    return (
        TimelineStore(modelContainer: container),
        SupportStore(modelContainer: container),
        AccountStore(modelContainer: container),
        UUID()
    )
}

private func status(_ id: String, createdAt: Date = Date()) -> Status {
    Status(
        id: id,
        createdAt: createdAt,
        content: "<p>Post \(id)</p>",
        account: Account(id: "1", username: "alice", acct: "alice@example.test")
    )
}

@Suite("Timeline store")
struct TimelineStorePersistenceTests {

    @Test("A cold page round-trips through the store")
    func coldPageRoundTrip() async throws {
        let (timelines, _, _, accountID) = makeStore()
        let page = ["3", "2", "1"].map { status($0) }

        let rows = try await timelines.apply(
            page: page, accountID: accountID, timelineKey: "home:home",
            direction: .cold, pageWasFull: false)

        #expect(rows.compactMap(\.status).map(\.id) == ["3", "2", "1"])

        let cached = try await timelines.cachedTimeline(
            accountID: accountID, timelineKey: "home:home")
        #expect(cached.compactMap(\.status).map(\.id) == ["3", "2", "1"])
    }

    @Test("A full refresh persists a gap row that survives a re-read")
    func gapPersists() async throws {
        let (timelines, _, _, accountID) = makeStore()

        _ = try await timelines.apply(
            page: ["3", "2", "1"].map { status($0) }, accountID: accountID,
            timelineKey: "home:home", direction: .cold, pageWasFull: false)

        _ = try await timelines.apply(
            page: ["9", "8", "7"].map { status($0) }, accountID: accountID,
            timelineKey: "home:home", direction: .newer, pageWasFull: true)

        let cached = try await timelines.cachedTimeline(
            accountID: accountID, timelineKey: "home:home")
        let gaps = cached.filter { if case .gap = $0 { return true } else { return false } }
        #expect(gaps.count == 1)
        #expect(cached.compactMap(\.status).map(\.id) == ["9", "8", "7", "3", "2", "1"])
    }

    @Test("A status is stored once and shared by two timelines")
    func statusesAreShared() async throws {
        let (timelines, _, _, accountID) = makeStore()
        let shared = status("42")

        _ = try await timelines.apply(
            page: [shared], accountID: accountID, timelineKey: "home:home",
            direction: .cold, pageWasFull: false)
        _ = try await timelines.apply(
            page: [shared], accountID: accountID, timelineKey: "photos:home",
            direction: .cold, pageWasFull: false)

        // Clearing one timeline must not remove the status the other still shows.
        _ = try await timelines.apply(
            page: [], accountID: accountID, timelineKey: "home:home",
            direction: .cold, pageWasFull: false)

        let photos = try await timelines.cachedTimeline(
            accountID: accountID, timelineKey: "photos:home")
        #expect(photos.compactMap(\.status).map(\.id) == ["42"])
    }

    @Test("A deletion removes the status from every timeline pointing at it")
    func deletionPropagates() async throws {
        let (timelines, _, _, accountID) = makeStore()

        _ = try await timelines.apply(
            page: ["3", "2", "1"].map { status($0) }, accountID: accountID,
            timelineKey: "home:home", direction: .cold, pageWasFull: false)
        _ = try await timelines.apply(
            page: [status("2")], accountID: accountID, timelineKey: "photos:home",
            direction: .cold, pageWasFull: false)

        try await timelines.deleteStatus(accountID: accountID, serverID: "2")

        let home = try await timelines.cachedTimeline(
            accountID: accountID, timelineKey: "home:home")
        let photos = try await timelines.cachedTimeline(
            accountID: accountID, timelineKey: "photos:home")
        #expect(home.compactMap(\.status).map(\.id) == ["3", "1"])
        #expect(photos.isEmpty)
    }

    @Test("Content kind is classified once, on insert")
    func classificationPersisted() async throws {
        let (timelines, _, _, accountID) = makeStore()
        var short = status("1")
        short.mediaAttachments = [
            MediaAttachment(
                id: "m", type: .video,
                meta: .init(original: .init(width: 1080, height: 1920, duration: 20)))
        ]

        _ = try await timelines.apply(
            page: [short], accountID: accountID, timelineKey: "shorts:home",
            direction: .cold, pageWasFull: false)

        let rows = try await timelines.cachedTimeline(
            accountID: accountID, timelineKey: "shorts:home")
        #expect(rows.count == 1)
    }

    @Test("Removing an account takes everything of that account's with it")
    func accountRemovalIsComplete() async throws {
        let (timelines, _, accounts, _) = makeStore()
        let snapshot = try await accounts.addAccount(
            instanceHost: "cloud.test",
            apiBase: URL(string: "https://cloud.test/")!,
            account: Account(id: "1", username: "alice", acct: "alice"),
            capabilities: .minimal(apiBase: URL(string: "https://cloud.test/")!))

        _ = try await timelines.apply(
            page: [status("1")], accountID: snapshot.id, timelineKey: "home:home",
            direction: .cold, pageWasFull: false)

        try await timelines.deleteEverything(forAccount: snapshot.id)

        #expect(try await accounts.allAccounts().isEmpty)
        #expect(
            try await timelines.cachedTimeline(
                accountID: snapshot.id, timelineKey: "home:home"
            ).isEmpty)
    }
}

@Suite("Markers")
struct MarkerTests {

    @Test("A marker never moves backwards")
    func markersAreMonotonic() async throws {
        let (_, support, _, accountID) = makeStore()

        #expect(try await support.advanceMarker(accountID: accountID, timeline: "home", to: "100"))
        // A device that is behind must not un-read what another has read.
        #expect(
            try await support.advanceMarker(accountID: accountID, timeline: "home", to: "50")
                == false)
        #expect(try await support.marker(accountID: accountID, timeline: "home") == "100")

        #expect(try await support.advanceMarker(accountID: accountID, timeline: "home", to: "101"))
        #expect(try await support.marker(accountID: accountID, timeline: "home") == "101")
    }

    @Test("Numeric ids of different lengths compare by magnitude, not lexically")
    func numericIDOrdering() {
        // Nextcloud Social uses numeric nids, so "1000" must beat "999".
        #expect(SupportStore.isNewer("1000", than: "999"))
        #expect(SupportStore.isNewer("999", than: "1000") == false)
        #expect(SupportStore.isNewer("1001", than: "1000"))
    }
}

@Suite("Watch positions")
struct WatchPositionTests {

    @Test("A finished video is forgotten rather than bookmarked at the credits")
    func completionForgets() async throws {
        let (_, support, _, accountID) = makeStore()

        try await support.recordWatchPosition(
            accountID: accountID, statusID: "v1", position: 300, duration: 1000)
        #expect(try await support.watchPosition(accountID: accountID, statusID: "v1") == 300)

        // Past 95 % the server forgets it; the client mirrors that.
        try await support.recordWatchPosition(
            accountID: accountID, statusID: "v1", position: 990, duration: 1000)
        #expect(try await support.watchPosition(accountID: accountID, statusID: "v1") == nil)
    }

    @Test("Nothing under ten seconds is worth reporting")
    func reportingThreshold() {
        #expect(WatchPositionRules.shouldReport(position: 4, duration: 600) == false)
        #expect(WatchPositionRules.shouldReport(position: 12, duration: 600))
    }
}

@Suite("Filters")
struct FilterStoreTests {

    @Test("An expired filter stops applying without a refetch")
    func expiredFiltersAreIgnored() async throws {
        let (_, support, _, accountID) = makeStore()
        let now = Date()

        try await support.replaceFilters(
            [
                Filter(id: "1", title: "Live", expiresAt: now.addingTimeInterval(3600)),
                Filter(id: "2", title: "Stale", expiresAt: now.addingTimeInterval(-60)),
                Filter(id: "3", title: "Forever"),
            ], accountID: accountID)

        let active = try await support.activeFilters(accountID: accountID, now: now)
        #expect(Set(active.map(\.title)) == ["Live", "Forever"])
    }
}

@Suite("Drafts")
struct DraftStoreTests {

    @Test("A draft round-trips and keeps its idempotency key")
    func draftRoundTrip() async throws {
        let (_, support, _, accountID) = makeStore()
        let draft = DraftSnapshot(
            accountID: accountID, text: "Hello", visibility: .private,
            idempotencyKey: "stable-key")

        _ = try await support.saveDraft(draft)
        let loaded = try await support.drafts(accountID: accountID)

        #expect(loaded.count == 1)
        #expect(loaded[0].text == "Hello")
        #expect(loaded[0].visibility == .private)
        // The key must survive a save/load cycle, or a retried send double-posts.
        #expect(loaded[0].idempotencyKey == "stable-key")
    }

    @Test("The send queue drains in thread order")
    func queueOrdering() async throws {
        let (_, support, _, accountID) = makeStore()
        let group = UUID()

        for index in [2, 0, 1] {
            _ = try await support.saveDraft(
                DraftSnapshot(
                    accountID: accountID, text: "Part \(index)", queuedForSend: true,
                    threadIndex: index, threadGroupID: group))
        }

        let queued = try await support.queuedDrafts(accountID: accountID)
        #expect(queued.map(\.threadIndex) == [0, 1, 2])
    }
}

@Suite("Notification dedup")
struct NotificationStoreTests {

    private func notification(_ id: String, count: Int = 1) -> StoredNotification {
        StoredNotification(
            serverID: id, isGroup: count > 1, kind: .mention, createdAt: Date(),
            groupCount: count, payload: Data(), statusServerID: nil)
    }

    @Test("The same notification is announced once")
    func announcedOnce() async throws {
        let (_, support, _, accountID) = makeStore()

        let first = try await support.storeNotifications([notification("n1")], accountID: accountID)
        #expect(first.count == 1)

        let second = try await support.storeNotifications(
            [notification("n1")], accountID: accountID)
        #expect(second.isEmpty)
    }

    @Test("A group that grew is announced again, replacing the old one")
    func growingGroupReannounces() async throws {
        let (_, support, _, accountID) = makeStore()

        _ = try await support.storeNotifications(
            [notification("favourite-9", count: 3)], accountID: accountID)
        let grown = try await support.storeNotifications(
            [notification("favourite-9", count: 40)], accountID: accountID)

        #expect(grown.count == 1)
        #expect(grown[0].groupCount == 40)
    }

    @Test("Marking announced stops it being raised twice")
    func markAnnounced() async throws {
        let (_, support, _, accountID) = makeStore()

        _ = try await support.storeNotifications([notification("n1")], accountID: accountID)
        #expect(try await support.unannouncedNotifications(accountID: accountID).count == 1)

        try await support.markAnnounced(accountID: accountID, serverIDs: ["n1"])
        #expect(try await support.unannouncedNotifications(accountID: accountID).isEmpty)
    }
}
