// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaUI

/// Handoff and Spotlight carry a post id, which is one server's id. These pin
/// that the account travels with it.
@Suite("Handoff, Spotlight and deep links")
@MainActor
struct ContinuityTests {
    @Test("A status link names its account")
    func statusLinkCarriesTheAccount() throws {
        let account = UUID()
        let url = try #require(URL(string: "alohasocial://status/\(account.uuidString)/99"))
        let destination = try #require(RouteResolver.destination(for: url))
        #expect(destination.accountID == account)
        #expect(destination.route == .thread(statusID: "99"))
    }

    @Test("The widgets' placeholder account is no account")
    func widgetPlaceholderIsNoAccount() throws {
        let url = try #require(URL(string: "alohasocial://status/0/99"))
        let destination = try #require(RouteResolver.destination(for: url))
        #expect(destination.accountID == nil)
        #expect(destination.route == .thread(statusID: "99"))
    }

    @Test("A Spotlight identifier resolves back to its post and its account")
    func spotlightIdentifierRoundTrips() throws {
        let account = UUID()
        let post = try #require(
            URL(string: SpotlightIndexer.identifier(statusID: "5", accountID: account)))
        #expect(
            RouteResolver.destination(for: post)
                == RouteDestination(accountID: account, route: .thread(statusID: "5")))

        let person = try #require(
            URL(string: SpotlightIndexer.identifier(profileID: "8", accountID: account)))
        #expect(
            RouteResolver.destination(for: person)
                == RouteDestination(accountID: account, route: .profile(accountID: "8")))
    }

    @Test("Each account's index lives under its own domain")
    func indexDomainsAreSeparate() {
        let first = UUID()
        let second = UUID()
        #expect(SpotlightIndexer.domain(for: first) != SpotlightIndexer.domain(for: second))
        #expect(SpotlightIndexer.domain(for: first).hasSuffix(first.uuidString))
    }

    @Test("A Handoff activity carries the route and the account")
    func activityCarriesAccount() {
        let activity = NSUserActivity(activityType: Continuity.viewingStatus)
        Continuity.configure(
            activity, route: .thread(statusID: "3"), title: "t",
            account: AccountIdentity(handle: "@me@example.test", host: "example.test"))
        #expect(Continuity.route(from: activity) == .thread(statusID: "3"))
        #expect(Continuity.accountHandle(from: activity) == "@me@example.test")
    }

    @Test("Public pages exist only where the web path is knowable")
    func webpageURLs() {
        #expect(
            Continuity.webpageURL(for: .hashtag("swift"), host: "example.test")?.absoluteString
                == "https://example.test/tags/swift")
        #expect(
            Continuity.webpageURL(for: .handle("@bob@other.test"), host: "example.test")?
                .absoluteString == "https://example.test/@bob@other.test")
        #expect(Continuity.webpageURL(for: .thread(statusID: "1"), host: "example.test") == nil)
    }

    @Test("Posts are server-specific; feeds are not")
    func serverSpecificRoutes() {
        #expect(Route.thread(statusID: "1").isServerSpecific)
        #expect(Route.profile(accountID: "1").isServerSpecific)
        #expect(!Route.notifications.isServerSpecific)
        #expect(!Route.hashtag("swift").isServerSpecific)
        #expect(!Route.collections(accountID: nil).isServerSpecific)
    }
}
