// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaUI

@Suite("Shell restoration")
struct ShellRestorationTests {
    private let account = UUID()

    private func restoration(
        tab: ShellTab = .mode(.photos),
        tabPaths: [ShellTab: [Route]] = [:],
        sidebarItem: SidebarItem = .mode(.home),
        sidebarPaths: [SidebarItem: [Route]] = [:]
    ) -> ShellRestoration {
        ShellRestoration(
            accountID: account, tab: tab, tabPaths: tabPaths,
            sidebarItem: sidebarItem, sidebarPaths: sidebarPaths)
    }

    @Test("Each tab's stack and the sidebar's survive encoding")
    func roundTrip() throws {
        let original = restoration(
            tab: .messages,
            tabPaths: [
                .mode(.home): [.thread(statusID: "109"), .profile(accountID: "7")],
                .messages: [.hashtag("swift")],
                .notifications: [.notificationPolicy],
            ],
            sidebarItem: .route(.explore),
            sidebarPaths: [
                .route(.explore): [.hashtag("photography")],
                .mode(.video): [.video(statusID: "42")],
            ])
        let data = try #require(original.encoded())
        let restored = try #require(ShellRestoration.decode(data, for: account))

        #expect(restored == original)
        #expect(restored.tab == .messages)
        #expect(restored.tabPaths[.mode(.home)] == [.thread(statusID: "109"), .profile(accountID: "7")])
        #expect(restored.restoredSidebarPaths[.route(.explore)] == [.hashtag("photography")])
        #expect(restored.sidebarItem.item == .route(.explore))
    }

    @Test("Another account's restoration is ignored")
    func otherAccountIsIgnored() throws {
        let data = try #require(restoration(tabPaths: [.messages: [.hashtag("a")]]).encoded())
        #expect(ShellRestoration.decode(data, for: UUID()) == nil)
    }

    @Test("Nothing stored, or something unreadable, restores nothing")
    func unreadableRestoresNothing() {
        #expect(ShellRestoration.decode(nil, for: account) == nil)
        #expect(ShellRestoration.decode(Data("not json".utf8), for: account) == nil)
    }

    @Test("Empty stacks are not stored, and deep ones keep only their newest screens")
    func trimming() {
        let deep = (0..<30).map { Route.thread(statusID: String($0)) }
        let stored = restoration(tabPaths: [.messages: [], .mode(.home): deep])
        #expect(stored.tabPaths[.messages] == nil)
        #expect(stored.tabPaths[.mode(.home)]?.count == ShellRestoration.maximumDepth)
        #expect(stored.tabPaths[.mode(.home)]?.last == .thread(statusID: "29"))
    }

    @Test("Activities is a tab only while the bar stays within five")
    func notificationsTabRespectsTheLimit() {
        // Two feeds or three: feeds, Messages and Activities fit.
        #expect(ShellTab.showsNotificationsTab(feedCount: 2))
        #expect(ShellTab.showsNotificationsTab(feedCount: 3))
        // The default four would make six, and a sixth tab is "More".
        #expect(!ShellTab.showsNotificationsTab(feedCount: FeedMode.defaultEnabled.count))
        #expect(!ShellTab.showsNotificationsTab(feedCount: 6))
    }
}

@Suite("Home marker")
struct HomeMarkerTests {
    @Test("The marker further along wins, from either side")
    func newestWins() {
        #expect(TimelineModel.newestMarker(local: "100", server: "200") == "200")
        #expect(TimelineModel.newestMarker(local: "300", server: "200") == "300")
        // Ids compare by length first: "1000" is newer than "999".
        #expect(TimelineModel.newestMarker(local: "999", server: "1000") == "1000")
    }

    @Test("Either one alone is the answer, and empty counts as absent")
    func oneSided() {
        #expect(TimelineModel.newestMarker(local: nil, server: "5") == "5")
        #expect(TimelineModel.newestMarker(local: "5", server: nil) == "5")
        #expect(TimelineModel.newestMarker(local: "", server: "5") == "5")
        #expect(TimelineModel.newestMarker(local: "5", server: "") == "5")
        #expect(TimelineModel.newestMarker(local: nil, server: nil) == nil)
    }
}

@Suite("Links rotor")
struct LinkRotorTests {
    @Test("A link is read as its host and path, without scheme or query")
    func labels() throws {
        let article = try #require(URL(string: "https://example.org/2026/10/news?utm=x"))
        #expect(LinkRotorEntry.label(for: article) == "example.org/2026/10/news")
        let home = try #require(URL(string: "https://example.org/"))
        #expect(LinkRotorEntry.label(for: home) == "example.org")
    }
}
