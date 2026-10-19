// SPDX-License-Identifier: MIT

import AlohaModels
import SwiftUI
import Testing

@testable import AlohaUI

/// An iPhone Duo is a phone: folded it gets the tab bar, unfolded the iPad's
/// sidebar shell, and the place a person was in survives the change.
@Suite("Shell layout")
struct ShellLayoutTests {
    #if os(iOS)
        @Test("The sidebar shell is for iPad and an unfolded phone, not a phone turned sideways")
        func whichShell() {
            #expect(ShellLayout.usesSidebar(idiom: .pad, horizontal: .compact, vertical: .regular))
            // iPhone Duo, unfolded: regular both ways.
            #expect(
                ShellLayout.usesSidebar(idiom: .phone, horizontal: .regular, vertical: .regular))
            // Folded, or any iPhone upright.
            #expect(
                !ShellLayout.usesSidebar(idiom: .phone, horizontal: .compact, vertical: .regular))
            // A Pro Max on its side: wide, but short.
            #expect(
                !ShellLayout.usesSidebar(idiom: .phone, horizontal: .regular, vertical: .compact))
        }
    #endif

    @Test("Unfolding keeps the tab and every tab's stack")
    func unfolding() {
        let state = ShellLayout.sidebarState(
            tab: .notifications,
            tabPaths: [
                .mode(.home): [.thread(statusID: "1")],
                .notifications: [.followRequests],
            ])
        #expect(state.item == .route(.notifications))
        #expect(state.paths[.mode(.home)] == [.thread(statusID: "1")])
        #expect(state.paths[.route(.notifications)] == [.followRequests])
    }

    @Test("Folding keeps a feed or Activities where it was")
    func foldingOntoATab() {
        let state = ShellLayout.tabState(
            item: .mode(.photos),
            sidebarPaths: [
                .mode(.photos): [.profile(accountID: "7")],
                .route(.notifications): [.notificationPolicy],
            ],
            feed: .home)
        #expect(state.tab == .mode(.photos))
        #expect(state.paths[.mode(.photos)] == [.profile(accountID: "7")])
        #expect(state.paths[.notifications] == [.notificationPolicy])
    }

    @Test("Folding on a place with no tab pushes it onto the feed, above what was there")
    func foldingOntoAPush() {
        let state = ShellLayout.tabState(
            item: .route(.conversations),
            sidebarPaths: [
                .mode(.home): [.thread(statusID: "1")],
                .route(.conversations): [.hashtag("swift")],
                .route(.explore): [.hashtag("photos")],
            ],
            feed: .home)
        #expect(state.tab == .mode(.home))
        #expect(
            state.paths[.mode(.home)] == [
                .thread(statusID: "1"), .conversations, .hashtag("swift"),
            ])
        // Only the place on show comes along; a row that was not selected
        // has no tab to keep its stack in.
        #expect(state.paths.count == 1)
    }
}
