// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaUI

/// Counts the searches a test's stub was asked for.
private actor SearchLog {
    private(set) var count = 0
    func record() { count += 1 }
}

private struct Unreachable: Error {}

@Suite("Fediverse links open in the app")
@MainActor
struct FediverseLinkTests {
    private let reader = UUID()
    private let bob = Account(
        id: "77", username: "bob", acct: "bob@other.test",
        url: URL(string: "https://other.test/@bob"),
        uri: URL(string: "https://other.test/users/bob"))

    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    // MARK: Which links are asked about

    @Test(
        "Post and profile addresses are candidates",
        arguments: [
            "https://m.test/@alice",
            "https://m.test/@alice/109",
            "https://m.test/@bob@other.test",
            "https://m.test/@bob@other.test/109",
            "https://m.test/users/alice",
            "https://m.test/users/alice/statuses/109",
            "https://cloud.test/apps/social/@alice/42",
            "https://cloud.test/index.php/apps/social/@alice",
            "https://pleroma.test/notice/AbC123",
            "https://akkoma.test/objects/0c5e-11",
            "https://misskey.test/notes/9abc",
            "https://pixelfed.test/p/alice/9",
            "https://tube.test/w/kkGMgK9ZtnKfYAgnEtQxbv",
            "https://tube.test/videos/watch/0b2b-4f1d",
        ])
    func candidates(_ link: String) throws {
        #expect(RouteResolver.isFediverseCandidate(try url(link)))
    }

    @Test(
        "Ordinary pages are not, and are never waited on",
        arguments: [
            "https://example.test/about",
            "https://example.test/",
            "http://m.test/@alice/109",
            "https://www.youtube.com/@channel",
            "https://medium.com/@writer/a-story-1234",
            "https://www.instagram.com/p/Cx1/",
            "https://m.test/@",
            "https://m.test/@alice/109/reblogs",
            "https://m.test/users/alice/followers",
            "https://m.test/p/report.pdf",
            "https://blog.test/notice/terms.html",
            "mailto:alice@m.test",
        ])
    func notCandidates(_ link: String) throws {
        #expect(!RouteResolver.isFediverseCandidate(try url(link)))
    }

    // MARK: Which answer is the link

    @Test("A status is taken when its url or uri is the link")
    func matchesStatus() throws {
        let post = Status(
            id: "local-5", uri: "https://other.test/users/bob/statuses/109",
            url: URL(string: "https://other.test/@bob/109"), account: bob)
        let results = SearchResults(statuses: [post])
        #expect(
            FediverseLinkResolver.route(
                for: try url("https://other.test/@bob/109/"), in: results)
                == .thread(statusID: "local-5"))
        #expect(
            FediverseLinkResolver.route(
                for: try url("https://OTHER.test/users/bob/statuses/109"), in: results)
                == .thread(statusID: "local-5"))
    }

    @Test("A profile is taken by its address, or by the handle another server's page spells")
    func matchesAccount() throws {
        let results = SearchResults(accounts: [bob])
        #expect(
            FediverseLinkResolver.route(for: try url("https://other.test/@bob"), in: results)
                == .profile(accountID: "77"))
        // Two accounts back, so only the handle can say which is meant.
        let crowded = SearchResults(
            accounts: [Account(id: "1", username: "bobby", acct: "bobby@x.test"), bob])
        #expect(
            FediverseLinkResolver.route(
                for: try url("https://mastodon.test/@bob@other.test"), in: crowded)
                == .profile(accountID: "77"))
    }

    @Test("A post that only mentions the link is not the link")
    func rejectsFullTextMatches() throws {
        let link = try url("https://other.test/@bob/109")
        let quoting = Status(
            id: "9",
            content: #"<p>Look: <a href="https://other.test/@bob/109">other.test/@bob/109</a></p>"#,
            account: Account(id: "3", username: "carol", acct: "carol"))
        #expect(
            FediverseLinkResolver.route(for: link, in: SearchResults(statuses: [quoting])) == nil)
        let two = SearchResults(
            statuses: [
                Status(id: "1", account: bob), Status(id: "2", account: bob),
            ])
        #expect(FediverseLinkResolver.route(for: link, in: two) == nil)
        #expect(FediverseLinkResolver.route(for: link, in: SearchResults()) == nil)
    }

    @Test("The lone thing a resolving server returns is taken, of the right kind")
    func loneResult() throws {
        let post = Status(id: "5", url: URL(string: "https://other.test/notes/zz"), account: bob)
        #expect(
            FediverseLinkResolver.route(
                for: try url("https://other.test/notice/abc"),
                in: SearchResults(statuses: [post])) == .thread(statusID: "5"))
        // A post's link that came back as an account is not that post.
        #expect(
            FediverseLinkResolver.route(
                for: try url("https://other.test/@bob/109"),
                in: SearchResults(accounts: [Account(id: "8", username: "x", acct: "x")]))
                == nil)
    }

    // MARK: Looking up, caching and falling back

    @Test("A found link opens in the app, and the second tap does not ask again")
    func cachesFound() async throws {
        let log = SearchLog()
        let resolver = FediverseLinkResolver()
        let link = try url("https://other.test/@bob")
        let search: FediverseLinkResolver.Search = { [bob] _ in
            await log.record()
            return SearchResults(accounts: [bob])
        }
        #expect(
            await resolver.lookup(link, accountID: reader, search: search)
                == .found(.profile(accountID: "77")))
        #expect(
            await resolver.lookup(link, accountID: reader, search: search)
                == .found(.profile(accountID: "77")))
        #expect(await log.count == 1)

        // Another account's server has its own ids, and is asked itself.
        _ = await resolver.lookup(link, accountID: UUID(), search: search)
        #expect(await log.count == 2)
    }

    @Test("Nothing found is remembered; a failure is not")
    func cachesOnlyAnswers() async throws {
        let log = SearchLog()
        let resolver = FediverseLinkResolver()
        let link = try url("https://other.test/@bob/109")

        let empty: FediverseLinkResolver.Search = { _ in
            await log.record()
            return SearchResults()
        }
        #expect(await resolver.lookup(link, accountID: reader, search: empty) == .nothingThere)
        #expect(await resolver.lookup(link, accountID: reader, search: empty) == .nothingThere)
        #expect(await log.count == 1)

        let other = try url("https://other.test/@bob/110")
        let failing: FediverseLinkResolver.Search = { _ in
            await log.record()
            throw Unreachable()
        }
        #expect(await resolver.lookup(other, accountID: reader, search: failing) == .failed)
        #expect(await resolver.lookup(other, accountID: reader, search: failing) == .failed)
        #expect(await log.count == 3)
    }

    @Test("A server slower than the timeout counts as a failure")
    func timesOut() async throws {
        let resolver = FediverseLinkResolver(timeout: .milliseconds(50))
        let slow: FediverseLinkResolver.Search = { _ in
            try await Task.sleep(for: .seconds(10))
            return SearchResults()
        }
        let start = ContinuousClock.now
        #expect(
            await resolver.lookup(
                try url("https://other.test/@bob/1"), accountID: reader, search: slow) == .failed)
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test("A tap opens the route, falls back to the browser, or goes straight there")
    func openDecides() async throws {
        let resolver = FediverseLinkResolver()
        let found: FediverseLinkResolver.Search = { [bob] _ in SearchResults(accounts: [bob]) }
        let failing: FediverseLinkResolver.Search = { _ in throw Unreachable() }
        var routes: [Route] = []
        var browsed: [URL] = []

        // Not a fediverse address: the browser, at once, without a lookup.
        let page = try url("https://example.test/about")
        resolver.open(
            page, accountID: reader, search: failing, onRoute: { routes.append($0) },
            fallback: { browsed.append($0) })
        #expect(browsed == [page])
        #expect(resolver.pending == nil)

        let profile = try url("https://other.test/@bob")
        resolver.open(
            profile, accountID: reader, search: found, onRoute: { routes.append($0) },
            fallback: { browsed.append($0) })
        #expect(resolver.pending == profile)
        try await waitUntil { resolver.pending == nil }
        #expect(routes == [.profile(accountID: "77")])

        let broken = try url("https://other.test/@bob/404")
        resolver.open(
            broken, accountID: reader, search: failing, onRoute: { routes.append($0) },
            fallback: { browsed.append($0) })
        try await waitUntil { resolver.pending == nil }
        #expect(browsed == [page, broken])

        // Cached: opens without waiting.
        resolver.open(
            profile, accountID: reader, search: failing, onRoute: { routes.append($0) },
            fallback: { browsed.append($0) })
        #expect(routes.count == 2)
        #expect(resolver.pending == nil)
    }

    @Test("Cancelling opens nothing")
    func cancelOpensNothing() async throws {
        let resolver = FediverseLinkResolver()
        let slow: FediverseLinkResolver.Search = { _ in
            try await Task.sleep(for: .seconds(10))
            return SearchResults()
        }
        var opened = false
        resolver.open(
            try url("https://other.test/@bob/2"), accountID: reader, search: slow,
            onRoute: { _ in opened = true }, fallback: { _ in opened = true })
        resolver.cancel()
        try await Task.sleep(for: .milliseconds(100))
        #expect(resolver.pending == nil)
        #expect(!opened)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
