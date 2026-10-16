// SPDX-License-Identifier: MIT
import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import Testing

@testable import AlohaUI

@Suite("Timeline page buffer")
@MainActor
struct TimelinePrefetchTests {
    @Test("The next page starts before the reader reaches the last post")
    func aheadOfEnd() {
        let ids = (0..<20).map(String.init)
        #expect(!TimelineModel.shouldPrefetchOlder(visibleID: "11", loadedIDs: ids))
        #expect(TimelineModel.shouldPrefetchOlder(visibleID: "12", loadedIDs: ids))
        #expect(TimelineModel.shouldPrefetchOlder(visibleID: "19", loadedIDs: ids))
    }

    @Test("Unknown and empty timelines do not trigger page requests")
    func noSpuriousRequests() {
        #expect(!TimelineModel.shouldPrefetchOlder(visibleID: "missing", loadedIDs: ["first"]))
        #expect(!TimelineModel.shouldPrefetchOlder(visibleID: "first", loadedIDs: []))
    }

    @Test("A short first page never requests another page")
    func shortHistoryStopsImmediately() async throws {
        let (model, server) = try await makeModel(statusCount: 3)
        await model.appear()
        #expect(model.rows.compactMap(\.status).count == 3)
        let before = await timelineRequests(server)
        #expect(before == 1)
        let last = try #require(model.rows.compactMap(\.status).last?.id)
        await model.prefetchOlder(near: last)
        await model.prefetchOlder(near: last)
        #expect(await timelineRequests(server) == before)
    }

    @Test("A final partial page stops subsequent buffered requests")
    func finalPartialPageStops() async throws {
        let total = Endpoint.defaultLimit + 5
        let (model, server) = try await makeModel(statusCount: total)
        await model.appear()
        #expect(model.rows.compactMap(\.status).count < total)
        await model.loadOlder()
        #expect(model.rows.compactMap(\.status).count == total)
        let before = await timelineRequests(server)
        await model.loadOlder()
        #expect(await timelineRequests(server) == before)
    }

    @Test("Overlapping near-end events share one older-page request")
    func overlappingRequestsAreBounded() async throws {
        let (model, server) = try await makeModel(statusCount: Endpoint.defaultLimit * 3 + 5)
        await model.appear()
        await server.delayOlderPages()
        async let first: Void = model.loadOlder()
        async let second: Void = model.loadOlder()
        _ = await (first, second)
        #expect(await timelineRequests(server) == 2)
        #expect(model.rows.compactMap(\.status).count == Endpoint.defaultLimit * 2)
    }

    @Test("A successful older-page retry clears the offline state")
    func retryClearsOfflineState() async throws {
        let total = Endpoint.defaultLimit + 5
        let (model, server) = try await makeModel(statusCount: total)
        await model.appear()
        await server.failNextOlderPage()
        await model.loadOlder()
        let wasOffline = model.isOffline
        #expect(wasOffline)
        #expect(model.rows.compactMap(\.status).count == Endpoint.defaultLimit)
        await model.loadOlder()
        #expect(!model.isOffline)
        #expect(model.errorMessage == nil)
        #expect(model.rows.compactMap(\.status).count == total)
    }

    private func timelineRequests(_ server: TimelineRecordingTransport) async -> Int {
        await server.loggedPaths.filter {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "api/v1/timelines/home"
        }.count
    }

    private func makeModel(
        statusCount: Int
    ) async throws -> (TimelineModel, TimelineRecordingTransport) {
        let server = MockAPIServer(configuration: .mastodon43, statusCount: statusCount)
        let transport = TimelineRecordingTransport(server: server)
        let container = StoreContainer.make(inMemory: true)
        let accounts = AccountStore(modelContainer: container)
        let base = try #require(URL(string: "https://cloud.example.test/"))
        let snapshot = try await accounts.addAccount(
            instanceHost: "cloud.example.test", apiBase: base,
            account: Account(id: "1", username: "alice", acct: "alice"),
            capabilities: .minimal(apiBase: base))
        let session = AccountSession(
            snapshot: snapshot, token: "test-token", transport: transport,
            timelines: TimelineStore(modelContainer: container),
            support: SupportStore(modelContainer: container), accounts: accounts)
        return (TimelineModel(key: .init(mode: .home, source: .home), session: session), transport)
    }

}

private actor TimelineRecordingTransport: HTTPTransport {
    let server: MockAPIServer
    var requests: [URL] = []
    private var delaysOlderPages = false
    private var failsNextOlderPage = false

    func failNextOlderPage() { failsNextOlderPage = true }

    func delayOlderPages() { delaysOlderPages = true }
    var loggedPaths: [String] { requests.map { $0.path() } }

    init(server: MockAPIServer) { self.server = server }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let url = request.url {
            requests.append(url)
            if failsNextOlderPage, url.query()?.contains("max_id=") == true {
                failsNextOlderPage = false
                throw APIError.transport(URLError(.notConnectedToInternet))
            }
            if delaysOlderPages, url.query()?.contains("max_id=") == true {
                try await Task.sleep(for: .milliseconds(25))
            }
        }
        return try await server.send(request)
    }
}
