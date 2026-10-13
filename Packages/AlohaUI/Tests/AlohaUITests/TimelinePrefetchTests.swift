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

    private func timelineRequests(_ server: TimelineRecordingTransport) async -> Int {
        await server.loggedPaths.filter { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "api/v1/timelines/home" }.count
    }

    private func makeModel(statusCount: Int) async throws -> (TimelineModel, TimelineRecordingTransport) {
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
    var loggedPaths: [String] { requests.map { $0.path() } }

    init(server: MockAPIServer) { self.server = server }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let url = request.url { requests.append(url) }
        return try await server.send(request)
    }
}
