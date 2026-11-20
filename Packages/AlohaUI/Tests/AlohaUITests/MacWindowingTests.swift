// SPDX-License-Identifier: MIT

import Foundation
import SwiftUI
import Testing

@testable import AlohaUI

/// The Mac's windowing rules: which account a window shows, where j and k
/// go, what Open Link… understands, the text size steps and the shortcut
/// table (docs/09 §2).
@Suite struct WindowAccountTests {
    private let alice = UUID()
    private let bob = UUID()

    @Test func aPinnedWindowShowsItsOwnAccount() {
        let id = WindowAccount.resolve(
            pinned: bob, stored: alice.uuidString, signedIn: [alice, bob], fallback: alice)
        #expect(id == bob)
    }

    @Test func aMainWindowShowsTheAccountItRemembers() {
        let id = WindowAccount.resolve(
            pinned: nil, stored: bob.uuidString, signedIn: [alice, bob], fallback: alice)
        #expect(id == bob)
    }

    @Test func aRemovedAccountFallsBackToTheDefault() {
        // Signed out elsewhere: the window must not keep a session that is gone.
        #expect(
            WindowAccount.resolve(
                pinned: bob, stored: bob.uuidString, signedIn: [alice], fallback: alice) == alice)
        #expect(
            WindowAccount.resolve(
                pinned: nil, stored: "not a uuid", signedIn: [alice], fallback: alice) == alice)
    }

    @Test func onlyTheFrontMainWindowTakesUpARequest() {
        let request = WindowAccount.Request(serial: 3, accountID: bob)
        #expect(WindowAccount.adopts(request, answered: 2, isFront: true, isPinned: false))
        // Another window: switching one window must not switch the others.
        #expect(!WindowAccount.adopts(request, answered: 2, isFront: false, isPinned: false))
        // A thread's own window keeps the account its post belongs to.
        #expect(!WindowAccount.adopts(request, answered: 2, isFront: true, isPinned: true))
    }

    @Test func aRequestIsTakenUpOnce() {
        let request = WindowAccount.Request(serial: 3, accountID: bob)
        #expect(!WindowAccount.adopts(request, answered: 3, isFront: true, isPinned: false))
        let empty = WindowAccount.Request(serial: 4, accountID: nil)
        #expect(!WindowAccount.adopts(empty, answered: 3, isFront: true, isPinned: false))
    }
}

@Suite struct StatusListCursorTests {
    private let ids = ["a", "b", "c", "d", "e"]

    @Test func jAndKStepOneRow() {
        #expect(StatusListCursor.next(after: "b", step: 1, ids: ids, visible: []) == "c")
        #expect(StatusListCursor.next(after: "b", step: -1, ids: ids, visible: []) == "a")
    }

    @Test func neitherEndWraps() {
        #expect(StatusListCursor.next(after: "e", step: 1, ids: ids, visible: []) == "e")
        #expect(StatusListCursor.next(after: "a", step: -1, ids: ids, visible: []) == "a")
    }

    @Test func theFirstMoveStartsFromWhatIsOnScreen() {
        let visible: Set = ["c", "d"]
        #expect(StatusListCursor.next(after: nil, step: 1, ids: ids, visible: visible) == "c")
        #expect(StatusListCursor.next(after: nil, step: -1, ids: ids, visible: visible) == "d")
        // Nothing reported on screen yet: the ends of the list.
        #expect(StatusListCursor.next(after: nil, step: 1, ids: ids, visible: []) == "a")
    }

    @Test func aSelectionScrolledAwayResumesOnScreen() {
        // Space paged past the selection; j carries on from the new page.
        let visible: Set = ["d", "e"]
        #expect(StatusListCursor.next(after: "a", step: 1, ids: ids, visible: visible) == "d")
        #expect(StatusListCursor.next(after: "a", step: -1, ids: ids, visible: visible) == "e")
    }

    @Test func aSelectionNoLongerInTheListStartsAgain() {
        #expect(StatusListCursor.next(after: "gone", step: 1, ids: ids, visible: []) == "a")
        #expect(StatusListCursor.next(after: "a", step: 1, ids: [], visible: []) == nil)
    }
}

@Suite struct OpenLinkInputTests {
    @Test func aPostAddressIsResolvedByTheServer() throws {
        let url = try #require(URL(string: "https://mastodon.social/@alice/1234"))
        #expect(OpenLinkInput("  https://mastodon.social/@alice/1234\n") == .web(url))
    }

    @Test func anAddressWithoutItsSchemeIsHTTPS() throws {
        let url = try #require(URL(string: "https://mastodon.social/@alice"))
        #expect(OpenLinkInput("mastodon.social/@alice") == .web(url))
    }

    @Test func aHandleOpensTheProfile() {
        #expect(OpenLinkInput("@alice@example.social") == .handle("alice@example.social"))
        #expect(OpenLinkInput("alice@example.social") == .handle("alice@example.social"))
    }

    @Test func theAppsOwnLinksAreRoutes() {
        #expect(OpenLinkInput("alohasocial://status/42") == .route(.thread(statusID: "42")))
    }

    @Test func nonsenseIsRefused() {
        #expect(OpenLinkInput("") == .invalid)
        #expect(OpenLinkInput("hello") == .invalid)
        #expect(OpenLinkInput("ftp://example.com/file") == .invalid)
        #expect(OpenLinkInput("@alice") == .invalid)
    }
}

@Suite struct MacTextSizeTests {
    @Test func stepZeroIsTheDefaultSize() {
        #expect(MacTextSize.size(forStep: 0) == .large)
    }

    @Test func stepsWalkTheDynamicTypeSizes() {
        #expect(MacTextSize.size(forStep: 1) == .xLarge)
        #expect(MacTextSize.size(forStep: -1) == .medium)
    }

    @Test func stepsBeyondTheRangeHoldAtItsEnds() {
        #expect(MacTextSize.size(forStep: -100) == MacTextSize.size(forStep: -3))
        #expect(MacTextSize.size(forStep: 100) == MacTextSize.size(forStep: 5))
        #expect(MacTextSize.size(forStep: 5) == .accessibility2)
    }
}

@Suite struct KeyboardShortcutsTests {
    @Test func noKeyIsListedForTwoThings() {
        let all = KeyboardShortcuts.timeline + KeyboardShortcuts.global + KeyboardShortcuts.post
        let keys = all.flatMap(\.keys)
        #expect(Set(keys).count == keys.count, "a key appears twice in the shortcut list")
    }

    #if os(macOS)
        @Test func theMacPostsWithCommandN() {
            // ⌘N is New Post, ⌥⌘N New Window, and the system's ⌥⌘M is left alone.
            let global = KeyboardShortcuts.global
            #expect(global.first { $0.keys == ["⌘N"] }?.label == "Write a new post")
            #expect(global.first { $0.keys == ["⌥⌘N"] }?.label == "Open a new window")
            #expect(!global.flatMap(\.keys).contains("⌥⌘M"))
        }
    #endif
}

#if os(macOS)
    @Suite struct SettingsPaneMemoryTests {
        typealias Selection = SettingsWindowView.Selection

        @Test func aSectionAndAPaneComeBack() {
            let section = Selection.section(.notifications)
            #expect(Selection(stored: section.stored, paneIDs: []) == section)
            let pane = Selection.pane("menu-bar")
            #expect(Selection(stored: pane.stored, paneIDs: ["menu-bar"]) == pane)
        }

        @Test func aPaneThatIsGoneOpensTheDefault() {
            #expect(Selection(stored: "pane:old", paneIDs: ["menu-bar"]) == nil)
            #expect(Selection(stored: "section:nothing", paneIDs: []) == nil)
            #expect(Selection(stored: "", paneIDs: []) == nil)
        }
    }
#endif
