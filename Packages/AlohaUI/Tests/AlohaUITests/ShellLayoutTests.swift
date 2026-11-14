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
            tab: .search,
            tabPaths: [
                .mode(.home): [.thread(statusID: "1")],
                .search: [.hashtag("swift")],
            ])
        #expect(state.item == .route(.search(query: nil)))
        #expect(state.paths[.mode(.home)] == [.thread(statusID: "1")])
        #expect(state.paths[.route(.search(query: nil))] == [.hashtag("swift")])
    }

    @Test("Folding keeps a feed or Search where it was")
    func foldingOntoATab() {
        let state = ShellLayout.tabState(
            item: .mode(.photos),
            sidebarPaths: [
                .mode(.photos): [.profile(accountID: "7")],
                .route(.search(query: nil)): [.hashtag("swift")],
            ],
            feed: .home)
        #expect(state.tab == .mode(.photos))
        #expect(state.paths[.mode(.photos)] == [.profile(accountID: "7")])
        #expect(state.paths[.search] == [.hashtag("swift")])
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

    // MARK: - The iPad's detail column

    @Test("Posts and profiles open in the detail column; places of their own do not")
    func whatOpensInTheDetailColumn() {
        #expect(ShellLayout.opensInDetailColumn(.thread(statusID: "1")))
        #expect(ShellLayout.opensInDetailColumn(.profile(accountID: "7")))
        #expect(ShellLayout.opensInDetailColumn(.handle("@a@example.com")))
        #expect(!ShellLayout.opensInDetailColumn(.hashtag("swift")))
        #expect(!ShellLayout.opensInDetailColumn(.settings))
    }

    @Test("With the column, a post replaces what it showed and the list stays put")
    func pushWithDetailColumn() {
        let next = ShellLayout.push(
            .thread(statusID: "2"), primary: [.hashtag("swift")],
            detail: [.thread(statusID: "1"), .profile(accountID: "7")],
            showsDetailColumn: true)
        #expect(next.primary == [.hashtag("swift")])
        #expect(next.detail == [.thread(statusID: "2")])

        let place = ShellLayout.push(
            .hashtag("photos"), primary: [], detail: [.thread(statusID: "1")],
            showsDetailColumn: true)
        #expect(place.primary == [.hashtag("photos")])
        #expect(place.detail == [.thread(statusID: "1")])
    }

    @Test("Without the column, everything is pushed above what the column had open")
    func pushWithoutDetailColumn() {
        let next = ShellLayout.push(
            .profile(accountID: "9"), primary: [.hashtag("swift")],
            detail: [.thread(statusID: "1")], showsDetailColumn: false)
        #expect(
            next.primary == [
                .hashtag("swift"), .thread(statusID: "1"), .profile(accountID: "9"),
            ])
        #expect(next.detail.isEmpty)
    }

    @Test("The detail column stays readable and never takes most of the window")
    func detailColumnWidth() {
        #expect(ShellLayout.detailColumnWidth(forWindowWidth: 1100) == 440)
        #expect(ShellLayout.detailColumnWidth(forWindowWidth: 800) == 420)
        #expect(ShellLayout.detailColumnWidth(forWindowWidth: 2000) == 600)
    }
}
