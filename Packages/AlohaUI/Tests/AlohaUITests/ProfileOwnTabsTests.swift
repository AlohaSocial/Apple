// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaUI

@Suite("Saved, Drafts and Statistics on your own profile")
struct ProfileOwnTabsTests {
    private let mastodon = ServerCapabilities(
        apiBase: URL(string: "https://mastodon.example")!, softwareName: "mastodon")
    private let social = ServerCapabilities(
        apiBase: URL(string: "https://cloud.example")!, softwareName: "nextcloud social",
        collections: true)

    @Test("Somebody else's profile has only the public tabs")
    func othersProfile() {
        #expect(
            ProfileView.tabs(isOwn: false, capabilities: mastodon) == [.posts, .photos, .videos])
        #expect(
            ProfileView.tabs(isOwn: false, capabilities: social)
                == [.posts, .photos, .videos, .tagged, .collections])
    }

    @Test("Your own profile adds Saved, Drafts and Statistics after the public tabs")
    func ownProfileOnSocial() {
        #expect(
            ProfileView.tabs(isOwn: true, capabilities: social)
                == [.posts, .photos, .videos, .tagged, .collections, .saved, .drafts, .statistics])
    }

    @Test("Statistics stays where the server keeps them")
    func statisticsNeedTheServer() {
        #expect(
            ProfileView.tabs(isOwn: true, capabilities: mastodon)
                == [.posts, .photos, .videos, .saved, .drafts])
    }

    @Test("Drafts has the web's sections, the server's own ones only where it has them")
    func draftSections() {
        #expect(
            ProfileView.draftSections(capabilities: social)
                == [.drafts, .scheduled, .waitingForReview, .archived])
        #expect(ProfileView.draftSections(capabilities: mastodon) == [.drafts, .scheduled])
    }

    @Test("Each route that had a screen of its own opens the matching tab")
    func routesOpenTheTab() {
        #expect(
            ProfileStart.ownTab(for: .favourites) == ProfileStart(tab: .saved, saved: .favorites))
        #expect(
            ProfileStart.ownTab(for: .bookmarks) == ProfileStart(tab: .saved, saved: .bookmarks))
        for route: Route in [.drafts, .scheduledPosts, .heldPosts, .archived] {
            #expect(ProfileStart.ownTab(for: route)?.tab == .drafts)
        }
        #expect(ProfileStart.ownTab(for: .statistics)?.tab == .statistics)
        #expect(ProfileStart.ownTab(for: .settings) == nil)
        #expect(ProfileStart.ownTab(for: .profile(accountID: "1")) == nil)
    }

    @Test("Widget and shortcut links still land on the tab")
    func deepLinksStillLand() throws {
        let expected: [(String, ProfileView.Tab)] = [
            ("alohasocial://bookmarks", .saved),
            ("alohasocial://favourites", .saved),
            ("alohasocial://drafts", .drafts),
            ("alohasocial://scheduled", .drafts),
            ("alohasocial://statistics", .statistics),
        ]
        for (link, tab) in expected {
            let url = try #require(URL(string: link))
            let route = try #require(RouteResolver.route(for: url))
            #expect(ProfileStart.ownTab(for: route)?.tab == tab, "\(link)")
        }
        let bookmarks = try #require(URL(string: "alohasocial://bookmarks"))
        #expect(
            RouteResolver.route(for: bookmarks).flatMap(ProfileStart.ownTab)?.saved == .bookmarks)
    }

    @Test("The moved places are pushed, not sidebar rows")
    func notSidebarRows() {
        for route in SidebarItem.sidebarRoutes {
            #expect(ProfileStart.ownTab(for: route) == nil)
        }
    }
}
