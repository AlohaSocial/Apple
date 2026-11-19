// SPDX-License-Identifier: MIT
import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import Testing

@testable import AlohaUI

@Suite("Timeline paging and gaps")
@MainActor
struct TimelinePagingTests {
    // MARK: - Past the cache's cap

    /// The rows on screen were whatever the cache handed back, and the
    /// cache keeps five hundred on Home: the list stopped there while the
    /// next page was asked for forever.
    @Test("Scrolling goes on past the rows the cache keeps")
    func pagingPastTheCap() async throws {
        let total = CachePolicy.homeTimelineLimit + 200
        let (model, _, session) = try await makeModel(statusCount: total)
        await model.appear()

        var pages = 0
        while model.canLoadOlder, pages < 40 {
            await model.loadOlder()
            pages += 1
        }

        let ids = model.rows.compactMap(\.status).map(\.id)
        #expect(ids.count == total)
        #expect(ids == (0..<total).map { String(1000 - $0) })
        #expect(!model.canLoadOlder)
        // What is kept for next launch is still capped.
        let cached = try await session.timelineStore.cachedTimeline(
            accountID: session.id, timelineKey: model.key.storageKey)
        #expect(cached.count == CachePolicy.homeTimelineLimit)
    }

    // MARK: - Where was I

    /// Away for a hundred and fifty posts: the refresh brings the newest
    /// forty and a gap. Filled from the top, as gaps were, the posts loaded
    /// joined the forty and never the post the reader was on. Filled from
    /// below, three pages connect them.
    @Test("Coming back fills the gap above the reader from below, until it closes")
    func catchUpFromBelow() async throws {
        let (model, server, _) = try await makeModel(statusCount: 100)
        await model.appear()
        #expect(model.rows.compactMap(\.status).count == Endpoint.homeTimelineLimit)
        // Reading, below the top, at the post they last saw.
        model.readerIsAtTop = false
        model.noteRow("1000", isVisible: true)

        await server.publishPosts(150)
        await model.refresh()
        #expect(model.pendingNewCount == Endpoint.homeTimelineLimit)

        await model.catchUpAboveReader()

        // Nothing moved under the reader; what arrived waits behind the pill.
        #expect(model.rows.compactMap(\.status).first?.id == "1000")
        #expect(model.pendingNewCount == 150)
        model.revealPendingRows()
        let ids = model.rows.compactMap(\.status).map(\.id)
        #expect(ids == (961...1150).reversed().map(String.init))
        #expect(!model.rows.contains { if case .gap = $0 { true } else { false } })
    }

    @Test("A gap the reader is below fills from below and keeps their post in place")
    func tappedGapBelowReader() async throws {
        let (model, server, _) = try await makeModel(statusCount: 100)
        await model.appear()
        // At the top, so the new posts go straight in, gap and all.
        model.readerIsAtTop = true
        await server.publishPosts(100)
        await model.refresh()
        let gapID = try #require(gapIDs(model).first)

        // Scrolled down past the gap to where they had been.
        model.readerIsAtTop = false
        model.noteRow("1000", isVisible: true)
        await model.fillGap(id: gapID)

        let ids = rowIDs(model)
        let gapIndex = try #require(ids.firstIndex(of: gapID))
        // The forty just newer than the reader's post, directly on top of
        // it, with the gap still above them.
        #expect(
            Array(ids[(gapIndex + 1)...].prefix(41)) == (1000...1040).reversed().map(String.init))
        #expect(model.keepInPlace?.statusID == "1000")
    }

    @Test("A gap the reader is above fills from above, as it always did")
    func tappedGapAboveReader() async throws {
        let (model, server, _) = try await makeModel(statusCount: 100)
        await model.appear()
        model.readerIsAtTop = true
        await server.publishPosts(100)
        await model.refresh()
        let gapID = try #require(gapIDs(model).first)

        model.noteRow("1100", isVisible: true)
        await model.fillGap(id: gapID)

        let ids = rowIDs(model)
        #expect(Array(ids.prefix(80)) == (1021...1100).reversed().map(String.init))
        #expect(model.keepInPlace == nil)
    }

    @Test("Home refreshes ask for forty posts")
    func homeRefreshAsksForForty() async throws {
        let (model, _, _) = try await makeModel(statusCount: 100)
        #expect(model.pageLimit == 40)
        await model.appear()
        #expect(model.rows.compactMap(\.status).count == 40)
    }

    // MARK: - Media feeds

    /// Photos filtered here, on a server that cannot: the newest two
    /// hundred posts have no picture in them. The first fetch finds
    /// nothing, and with no tile on screen nothing ever asked again.
    @Test("A media feed keeps fetching through pages the filter emptied")
    func mediaFeedDoesNotStall() async throws {
        let (model, server, _) = try await makeModel(
            statusCount: 40, key: TimelineKey(mode: .photos, source: .home))
        await server.publishPosts(200)

        await model.appear()

        #expect(await eventually { !model.rows.isEmpty && !model.isPagingOlder })
        #expect(
            model.rows.compactMap(\.status).allSatisfy {
                !$0.displayed.mediaAttachments.isEmpty
            })
    }

    // MARK: - Empty state

    @Test("Nothing is called empty before the first load has come back")
    func emptyStateWaitsForTheFirstLoad() async throws {
        let (model, _, _) = try await makeModel(statusCount: 0)
        #expect(!model.showsEmptyState)
        #expect(model.isLoadingFirstPage)

        await model.appear()

        #expect(model.showsEmptyState)
        #expect(!model.isLoadingFirstPage)
    }

    // MARK: - Helpers

    private func rowIDs(_ model: TimelineModel) -> [String] {
        model.rows.filter {
            if case .caughtUpDivider = $0 { return false }
            return true
        }.map(\.id)
    }

    private func gapIDs(_ model: TimelineModel) -> [String] {
        model.rows.compactMap { row in
            if case .gap(let id) = row { return id }
            return nil
        }
    }

    private func eventually(
        within timeout: Duration = .seconds(10), _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    private func makeModel(
        statusCount: Int, key: TimelineKey = TimelineKey(mode: .home, source: .home)
    ) async throws -> (TimelineModel, MockAPIServer, AccountSession) {
        let server = MockAPIServer(configuration: .mastodon43, statusCount: statusCount)
        let container = StoreContainer.make(inMemory: true)
        let accounts = AccountStore(modelContainer: container)
        let base = try #require(URL(string: "https://cloud.example.test/"))
        let snapshot = try await accounts.addAccount(
            instanceHost: "cloud.example.test", apiBase: base,
            account: Account(id: "1", username: "alice", acct: "alice"),
            capabilities: .minimal(apiBase: base))
        let session = AccountSession(
            snapshot: snapshot, token: "test-token", transport: server,
            timelines: TimelineStore(modelContainer: container),
            support: SupportStore(modelContainer: container), accounts: accounts)
        return (TimelineModel(key: key, session: session), server, session)
    }
}
