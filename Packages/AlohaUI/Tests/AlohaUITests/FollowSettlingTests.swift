// SPDX-License-Identifier: MIT
import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import Testing

@testable import AlohaUI

@Suite("Pending follow settling")
@MainActor
struct FollowSettlingTests {
    @Test("A pending follow of an open account is asked again until accepted")
    func settlesOnAccept() async throws {
        let transport = RelationshipTransport(answers: [
            relationships(following: false, requested: true),
            relationships(following: true, requested: false),
            relationships(following: true, requested: false),
        ])
        let session = try await makeSession(transport)
        var seen: [Relationship] = []
        await session.settleFollow(
            Relationship(id: "7", requested: true), locked: false,
            waits: [.zero, .zero, .zero]
        ) { seen.append($0) }

        #expect(seen.map(\.following) == [false, true])
        #expect(await transport.requests == 2)
    }

    @Test("A locked account's request waits for a person, so nothing is asked")
    func lockedIsLeftAlone() async throws {
        let transport = RelationshipTransport(answers: [])
        let session = try await makeSession(transport)
        var seen: [Relationship] = []
        await session.settleFollow(
            Relationship(id: "7", requested: true), locked: true, waits: [.zero]
        ) { seen.append($0) }

        #expect(seen.isEmpty)
        #expect(await transport.requests == 0)
    }

    @Test("An accepted follow is not asked again")
    func acceptedIsLeftAlone() async throws {
        let transport = RelationshipTransport(answers: [])
        let session = try await makeSession(transport)
        await session.settleFollow(
            Relationship(id: "7", following: true), locked: false, waits: [.zero]
        ) { _ in }

        #expect(await transport.requests == 0)
    }

    @Test("The checks stop when they run out")
    func stopsAfterLastCheck() async throws {
        let pending = relationships(following: false, requested: true)
        let transport = RelationshipTransport(answers: [pending, pending, pending])
        let session = try await makeSession(transport)
        await session.settleFollow(
            Relationship(id: "7", requested: true), locked: false, waits: [.zero, .zero]
        ) { _ in }

        #expect(await transport.requests == 2)
    }

    private func makeSession(_ transport: RelationshipTransport) async throws -> AccountSession {
        let container = StoreContainer.make(inMemory: true)
        let accounts = AccountStore(modelContainer: container)
        let base = try #require(URL(string: "https://cloud.example.test/"))
        let snapshot = try await accounts.addAccount(
            instanceHost: "cloud.example.test", apiBase: base,
            account: Account(id: "1", username: "alice", acct: "alice"),
            capabilities: .minimal(apiBase: base))
        return AccountSession(
            snapshot: snapshot, token: "test-token", transport: transport,
            timelines: TimelineStore(modelContainer: container),
            support: SupportStore(modelContainer: container), accounts: accounts)
    }
}

private func relationships(following: Bool, requested: Bool) -> String {
    """
    [{"id": "7", "following": \(following), "followed_by": false, "blocking": false,
      "blocked_by": false, "muting": false, "muting_notifications": false,
      "requested": \(requested), "requested_by": false, "domain_blocking": false,
      "endorsed": false, "notifying": false}]
    """
}

/// Answers `api/v1/accounts/relationships` with the scripted bodies in order.
private actor RelationshipTransport: HTTPTransport {
    private var answers: [String]
    private(set) var requests = 0

    init(answers: [String]) { self.answers = answers }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = try #require(request.url)
        #expect(url.path().hasSuffix("api/v1/accounts/relationships"))
        requests += 1
        let body = answers.isEmpty ? "[]" : answers.removeFirst()
        let response = try #require(
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        return (Data(body.utf8), response)
    }

    nonisolated func removeCachedResponses() {}
}
