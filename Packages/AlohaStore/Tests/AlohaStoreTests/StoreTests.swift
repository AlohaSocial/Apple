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

    /// What a reviewer saw: forty posts filled into the gap a full refresh
    /// left, read back by position, came out as 62, 61, 60, 59, 20, 58, 19…
    /// The merge's own answer was in order; only the stored one was not, so
    /// this reads the timeline back the way a launch does.
    @Test("Filling a gap a page at a time keeps the stored order")
    func gapFillKeepsStoredOrder() async throws {
        let (timelines, _, _, accountID) = makeStore()
        let key = "home:home"
        func page(_ ids: ClosedRange<Int>) -> [Status] { ids.reversed().map { status("\($0)") } }
        func stored() async throws -> [TimelineMerge.Slot] {
            try await timelines.slots(accountID: accountID, timelineKey: key)
        }
        func gapID() async throws -> String {
            let gap = try await stored().first { $0.isGapMarker }
            return try #require(gap).statusID
        }

        _ = try await timelines.apply(
            page: page(1...20), accountID: accountID, timelineKey: key,
            direction: .cold, pageWasFull: false)
        _ = try await timelines.apply(
            page: page(201...240), accountID: accountID, timelineKey: key,
            direction: .newer, pageWasFull: true)

        // Three full pages walk the gap down; each one has less room than
        // the last, and the third has none.
        for range in [161...200, 121...160, 81...120] {
            _ = try await timelines.apply(
                page: page(range), accountID: accountID, timelineKey: key,
                direction: .fillingGap(id: try await gapID()), pageWasFull: true)
            #expect(TimelineMerge.isWellFormed(try await stored()))
        }
        _ = try await timelines.apply(
            page: page(21...80), accountID: accountID, timelineKey: key,
            direction: .fillingGap(id: try await gapID()), pageWasFull: false)

        #expect(TimelineMerge.isWellFormed(try await stored()))
        let cached = try await timelines.cachedTimeline(accountID: accountID, timelineKey: key)
        #expect(cached.allSatisfy { $0.status != nil })
        #expect(cached.compactMap(\.status).map(\.id) == (1...240).reversed().map { "\($0)" })
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

    @Test("Everything a queued post needs to resend survives a save/load cycle")
    func fullRoundTrip() async throws {
        let (_, support, _, accountID) = makeStore()
        let scheduled = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = DraftSnapshot(
            accountID: accountID, text: "Look", spoilerText: "food", visibility: .unlisted,
            sensitive: true, language: "de", inReplyToID: "5", uploadedMediaIDs: ["m1"],
            pollOptions: [], pollExpiresIn: 3600, scheduledAt: scheduled,
            idempotencyKey: "key", queuedForSend: true, quotedID: "9", quotePolicy: "nobody",
            threadSegments: ["second", "third"])

        _ = try await support.saveDraft(draft)
        let loaded = try #require(try await support.drafts(accountID: accountID).first)

        #expect(loaded.sensitive)
        #expect(loaded.language == "de")
        #expect(loaded.scheduledAt == scheduled)
        #expect(loaded.quotedID == "9")
        #expect(loaded.quotePolicy == "nobody")
        #expect(loaded.threadSegments == ["second", "third"])
        #expect(loaded.uploadedMediaIDs == ["m1"])
    }

    @Test("A draft the server refused leaves the queue and says why")
    func sendFailure() async throws {
        let (_, support, _, accountID) = makeStore()
        let id = try await support.saveDraft(
            DraftSnapshot(accountID: accountID, text: "Hi", queuedForSend: true))

        try await support.markSendFailed(id: id, message: "Too long")

        #expect(try await support.queuedDrafts(accountID: accountID).isEmpty)
        let kept = try #require(try await support.drafts(accountID: accountID).first)
        #expect(kept.lastSendError == "Too long")
        #expect(kept.text == "Hi")
    }

    @Test("A quote with nothing typed is not an empty draft")
    func quoteIsContent() {
        let draft = DraftSnapshot(accountID: UUID(), quotedID: "9")
        #expect(!draft.isEmpty)
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

    @Test("An account's first fetch is history, not forty notifications at once")
    func firstFetchIsSeeded() async throws {
        let (_, support, accounts, _) = makeStore()
        let base = try #require(URL(string: "https://example.test/"))
        let account = try await accounts.addAccount(
            instanceHost: "example.test", apiBase: base,
            account: Account(id: "1", username: "alice", acct: "alice"),
            capabilities: .minimal(apiBase: base))
        let old = (0..<40).map { index in
            StoredNotification(
                serverID: "old-\(index)", isGroup: false, kind: .mention,
                createdAt: Date().addingTimeInterval(-3_600), groupCount: 1, payload: Data(),
                statusServerID: nil)
        }
        // Something that arrived after signing in is still news.
        let fresh = StoredNotification(
            serverID: "fresh", isGroup: false, kind: .mention,
            createdAt: Date().addingTimeInterval(60), groupCount: 1, payload: Data(),
            statusServerID: nil)

        let announced = try await support.storeNotifications(
            old + [fresh], accountID: account.id)

        #expect(announced.map(\.serverID) == ["fresh"])
        #expect(try await support.unannouncedNotifications(accountID: account.id).count == 1)
    }

    @Test("Marking announced stops it being raised twice")
    func markAnnounced() async throws {
        let (_, support, _, accountID) = makeStore()

        _ = try await support.storeNotifications([notification("n1")], accountID: accountID)
        #expect(try await support.unannouncedNotifications(accountID: accountID).count == 1)

        try await support.markAnnounced(accountID: accountID, serverIDs: ["n1"])
        #expect(try await support.unannouncedNotifications(accountID: accountID).isEmpty)
    }

    @Test("What quiet hours held back is offered on the next poll, though nothing new came")
    func heldIsOfferedAgain() async throws {
        let (_, support, _, accountID) = makeStore()
        let since = Date().addingTimeInterval(-12 * 3600)

        // 23:00: it arrives, quiet hours hold it, nothing is marked announced.
        let first = try await support.storeNotifications([notification("n1")], accountID: accountID)
        #expect(first.count == 1)

        // 07:00: the next poll brings nothing new, and the held one is offered.
        let nothingNew = try await support.storeNotifications(
            [notification("n1")], accountID: accountID)
        let offered = try await support.pendingAnnouncements(
            arrived: nothingNew, accountID: accountID, since: since)
        #expect(offered.map(\.serverID) == ["n1"])

        // Raised, it is not offered a third time.
        try await support.markAnnounced(accountID: accountID, serverIDs: ["n1"])
        let after = try await support.pendingAnnouncements(
            arrived: [], accountID: accountID, since: since)
        #expect(after.isEmpty)
    }

    @Test("A new arrival and a held one are offered once each, newest first")
    func arrivedAndHeldTogether() async throws {
        let (_, support, _, accountID) = makeStore()
        let held = StoredNotification(
            serverID: "held", isGroup: false, kind: .mention,
            createdAt: Date().addingTimeInterval(-600), groupCount: 1, payload: Data(),
            statusServerID: nil)
        _ = try await support.storeNotifications([held], accountID: accountID)
        let arrived = try await support.storeNotifications(
            [notification("new")], accountID: accountID)

        let offered = try await support.pendingAnnouncements(
            arrived: arrived, accountID: accountID, since: Date().addingTimeInterval(-3600))
        #expect(offered.map(\.serverID) == ["new", "held"])
    }

    @Test("Held ones from before the window, and past the limit, are not offered")
    func windowAndLimit() async throws {
        let (_, support, _, accountID) = makeStore()
        let stale = StoredNotification(
            serverID: "yesterday", isGroup: false, kind: .mention,
            createdAt: Date().addingTimeInterval(-2 * 86_400), groupCount: 1, payload: Data(),
            statusServerID: nil)
        let recent = (0..<30).map { index in
            StoredNotification(
                serverID: "r\(index)", isGroup: false, kind: .mention,
                createdAt: Date().addingTimeInterval(Double(-index * 60)), groupCount: 1,
                payload: Data(), statusServerID: nil)
        }
        _ = try await support.storeNotifications([stale] + recent, accountID: accountID)

        let offered = try await support.pendingAnnouncements(
            arrived: [], accountID: accountID, since: Date().addingTimeInterval(-12 * 3600),
            limit: 20)
        #expect(offered.count == 20)
        #expect(!offered.contains { $0.serverID == "yesterday" })
        #expect(offered.first?.serverID == "r0")
    }
}
