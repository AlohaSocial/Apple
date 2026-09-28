// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaUI

private func makeStatus(content: String, spoiler: String = "", id: String = "1") -> Status {
    Status(
        id: id, content: content, spoilerText: spoiler,
        account: Account(id: "1", username: "alice", acct: "alice"))
}

@Suite("Client-side filtering")
struct FilterEvaluatorTests {

    private func filter(
        _ keyword: String, action: FilterAction = .hide, wholeWord: Bool = false,
        contexts: [FilterContext] = [.home], expires: Date? = nil
    ) -> Filter {
        Filter(
            id: "f1", title: "Test", context: contexts, expiresAt: expires,
            filterAction: action,
            keywords: [Filter.Keyword(id: "k1", keyword: keyword, wholeWord: wholeWord)])
    }

    @Test("A hide filter removes the row")
    func hideRemoves() {
        let decision = FilterEvaluator.decision(
            for: makeStatus(content: "<p>talking about spoilers here</p>"),
            filters: [filter("spoilers")], context: .home)
        #expect(decision == .hide)
    }

    @Test("A warn filter collapses behind its title")
    func warnCollapses() {
        let decision = FilterEvaluator.decision(
            for: makeStatus(content: "<p>election news</p>"),
            filters: [filter("election", action: .warn)], context: .home)
        #expect(decision == .warn(title: "Test"))
    }

    @Test("A filter only applies in the contexts it names")
    func contextScoping() {
        let onlyHome = filter("spoilers", contexts: [.home])
        let status = makeStatus(content: "<p>spoilers</p>")

        #expect(FilterEvaluator.decision(for: status, filters: [onlyHome], context: .home) == .hide)
        #expect(
            FilterEvaluator.decision(for: status, filters: [onlyHome], context: .public) == .show)
    }

    /// The reason filters are applied at render time rather than at insert:
    /// one that expires has to stop hiding without a refetch (docs/04 §6).
    @Test("An expired filter stops applying immediately")
    func expiryStopsApplying() {
        let now = Date()
        let stale = filter("spoilers", expires: now.addingTimeInterval(-60))
        let status = makeStatus(content: "<p>spoilers</p>")

        #expect(
            FilterEvaluator.decision(for: status, filters: [stale], context: .home, now: now)
                == .show)
    }

    @Test("Whole-word matching does not fire on a substring")
    func wholeWordMatching() {
        let wholeWord = filter("art", wholeWord: true)

        #expect(
            FilterEvaluator.decision(
                for: makeStatus(content: "<p>a partial match</p>"),
                filters: [wholeWord], context: .home) == .show)
        #expect(
            FilterEvaluator.decision(
                for: makeStatus(content: "<p>some art here</p>"),
                filters: [wholeWord], context: .home) == .hide)
    }

    @Test("The content warning is searched as well as the body")
    func spoilerTextIsSearched() {
        let decision = FilterEvaluator.decision(
            for: makeStatus(content: "<p>nothing</p>", spoiler: "election talk"),
            filters: [filter("election")], context: .home)
        #expect(decision == .hide)
    }

    @Test("Hiding wins over warning when two filters match")
    func hideWinsOverWarn() {
        let status = makeStatus(content: "<p>spoilers and election</p>")
        var warnFilter = filter("election", action: .warn)
        warnFilter.id = "f2"

        let decision = FilterEvaluator.decision(
            for: status, filters: [filter("spoilers"), warnFilter], context: .home)
        #expect(decision == .hide)
    }

    @Test("A boost is judged by what it boosts")
    func boostsUseTheirPayload() {
        let inner = makeStatus(content: "<p>spoilers inside</p>", id: "inner")
        let boost = Status(
            id: "boost", content: "",
            account: Account(id: "2", username: "bob", acct: "bob"),
            reblog: Box(inner))

        #expect(
            FilterEvaluator.decision(for: boost, filters: [filter("spoilers")], context: .home)
                == .hide)
    }

    @Test("An empty keyword never matches everything")
    func emptyKeywordIsInert() {
        #expect(
            FilterEvaluator.decision(
                for: makeStatus(content: "<p>anything</p>"),
                filters: [filter("")], context: .home) == .show)
    }
}

@Suite("Route resolution")
struct RouteResolverTests {

    @Test("Every scheme form resolves")
    func schemeForms() throws {
        #expect(
            RouteResolver.route(for: URL(string: "alohasocial://status/abc/109")!)
                == .thread(statusID: "109"))
        #expect(
            RouteResolver.route(for: URL(string: "alohasocial://profile/abc/42")!)
                == .profile(accountID: "42"))
        #expect(
            RouteResolver.route(for: URL(string: "alohasocial://tag/swift")!) == .hashtag("swift"))
        #expect(
            RouteResolver.route(for: URL(string: "alohasocial://notifications")!) == .notifications)
        #expect(
            RouteResolver.route(for: URL(string: "alohasocial://search?q=hello")!)
                == .search(query: "hello"))
    }

    @Test("A timeline link carries its mode and source")
    func timelineForms() {
        #expect(
            RouteResolver.route(for: URL(string: "alohasocial://timeline/shorts/federated")!)
                == .timeline(TimelineKey(mode: .shorts, source: .federated)))
        #expect(
            RouteResolver.route(for: URL(string: "alohasocial://timeline/photos")!)
                == .timeline(TimelineKey(mode: .photos, source: .home)))
    }

    @Test("Another app's scheme is not ours to handle")
    func foreignSchemes() {
        #expect(RouteResolver.route(for: URL(string: "https://example.test/@alice")!) == nil)
        #expect(RouteResolver.route(for: URL(string: "otherapp://status/1")!) == nil)
    }

    /// Resolving a fediverse URL through the reading account's own server is
    /// what makes a remote post open with working action buttons (docs/09 §10).
    @Test("Fediverse URLs are recognised for resolution")
    func fediverseCandidates() {
        #expect(RouteResolver.isFediverseCandidate(URL(string: "https://m.test/@alice/109")!))
        #expect(RouteResolver.isFediverseCandidate(URL(string: "https://m.test/users/alice")!))
        #expect(RouteResolver.isFediverseCandidate(URL(string: "https://pixelfed.test/p/alice/9")!))
        #expect(
            RouteResolver.isFediverseCandidate(URL(string: "https://example.test/about")!) == false)
    }

    @Test("A route round-trips through Codable, which is what Handoff needs")
    func routeIsCodable() throws {
        let routes: [Route] = [
            .timeline(TimelineKey(mode: .video, source: .list(id: "3"))),
            .thread(statusID: "109"),
            .profile(accountID: "42"),
            .hashtag("swift"),
            .settings,
        ]
        for route in routes {
            let data = try JSONEncoder().encode(route)
            #expect(try JSONDecoder().decode(Route.self, from: data) == route)
        }
    }
}
