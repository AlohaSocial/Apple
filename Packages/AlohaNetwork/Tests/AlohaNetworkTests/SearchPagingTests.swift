// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaNetwork

@Suite("Search narrowed to one kind")
struct SearchPagingTests {
    @Test("A page names its kind and sends an offset only past the first page")
    func query() {
        let first = Endpoint.search.page("cats", type: .accounts)
        #expect(first.path == "api/v2/search")
        #expect(first.query.first { $0.name == "type" }?.value == "accounts")
        #expect(first.query.first { $0.name == "offset" } == nil)
        #expect(first.query.first { $0.name == "resolve" } == nil)

        let later = Endpoint.search.page(
            "cats", type: .statuses, offset: 40, limit: 500, resolve: true)
        #expect(later.query.first { $0.name == "offset" }?.value == "40")
        #expect(later.query.first { $0.name == "limit" }?.value == "50")
        #expect(later.query.first { $0.name == "resolve" }?.value == "true")
    }

    @Test("The mock pages one kind and leaves the others empty")
    func pagesAgainstMock() async throws {
        let client = APIClient(
            accountID: UUID(), apiBase: URL(string: "https://cloud.example.test/")!,
            accessToken: "token", transport: MockAPIServer(configuration: .mastodon43))

        let first = try await client.decode(
            SearchResults.self, from: Endpoint.search.page("", type: .accounts, limit: 1))
        #expect(first.accounts.map(\.username) == ["alice"])
        #expect(first.hashtags.isEmpty && first.statuses.isEmpty)

        let second = try await client.decode(
            SearchResults.self,
            from: Endpoint.search.page("", type: .accounts, offset: 1, limit: 1))
        #expect(second.accounts.map(\.username) == ["bob"])

        let past = try await client.decode(
            SearchResults.self,
            from: Endpoint.search.page("", type: .accounts, offset: 2, limit: 1))
        #expect(past.accounts.isEmpty)
    }
}
