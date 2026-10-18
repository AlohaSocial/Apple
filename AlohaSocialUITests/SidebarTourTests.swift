// SPDX-License-Identifier: MIT

import XCTest

#if canImport(UIKit)
    import UIKit
#endif

#if os(macOS) || os(iOS)
    /// The split-view shell: every sidebar row must change the detail column.
    /// `@MainActor` because every `XCUIElement` member is: without it each
    /// `tap()` and `waitForExistence` is a nonisolated call into main-actor
    /// state, which is a warning per line and a build failure once warnings
    /// are errors (docs/12 §6).
    @MainActor
    final class SidebarTourTests: XCTestCase {
        private var app: XCUIApplication!

        // The `async` overrides, not `setUpWithError`/`tearDown`: XCTest
        // declares those nonisolated, so an override of one stays nonisolated
        // even in a `@MainActor` class, and every line here touches
        // `XCUIApplication`, which is main-actor. The async forms adopt the
        // class's isolation instead.
        override func setUp() async throws {
            continueAfterFailure = true
            app = XCUIApplication()
            app.launchArguments = ["-AlohaMockServer"]
            app.launch()
            #if os(iOS)
                app.dismissSystemAlertsIfPresent()
            #endif
        }

        /// Deeper than the sidebar: the screens a click on content reaches.
        func testContentScreensOnSplitShell() throws {
            continueAfterFailure = false
            #if os(iOS)
                try XCTSkipIf(
                    UIDevice.current.userInterfaceIdiom != .pad, "Sidebar exists on iPad only")
            #endif
            XCTAssertTrue(app.labelled("Alice").waitForExistence(timeout: 20))

            // Thread from a row body.
            let body = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH 'Test post number 1 with'")
            ).firstMatch
            XCTAssertTrue(body.waitForExistence(timeout: 5))
            body.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tapOrClick()
            XCTAssertTrue(
                app.labelled("Reply 1 to that").waitForExistence(timeout: 8), "Thread did not open")
            shoot("22-split-thread")

            // Profile from the avatar in the focused post.
            let profile = app.collectionViews.staticTexts["Alice"].firstMatch
            XCTAssertTrue(profile.waitForExistence(timeout: 5))
            profile.tapOrClick()
            XCTAssertTrue(
                app.labelled("Followers").waitForExistence(timeout: 8), "Profile did not open")
            shoot("23-split-profile")

            // Composer, type, post.
            app.buttons["New post"].firstMatch.tapOrClick()
            let editor = app.textViews.firstMatch
            XCTAssertTrue(editor.waitForExistence(timeout: 5), "No editor")
            editor.tapOrClick()
            editor.typeText("Posted from the split shell")
            shoot("24-split-composer")
            app.buttons["Post"].firstMatch.tapOrClick()
            sleep(2)

            // Explore with data.
            app.sidebarRow("Discover").tapOrClick()
            XCTAssertTrue(
                app.labelled("People to follow").waitForExistence(timeout: 8),
                "Discover has no people section")
            shoot("25-split-explore")

            // Lists with data.
            app.sidebarRow("Your lists").tapOrClick()
            XCTAssertTrue(app.labelled("Colleagues").waitForExistence(timeout: 8), "Lists empty")
            shoot("26-split-lists")

            // Conversations.
            app.sidebarRow("Direct messages").tapOrClick()
            sleep(2)
            shoot("27-split-conversations")

            // The search field at the top of the sidebar, where the web has it.
            #if os(iOS)
                app.sidebarRow("Search").tapOrClick()
            #endif
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5), "No search field in the sidebar")
            field.tapOrClick()
            field.typeText("alice\n")
            XCTAssertTrue(
                app.labelled("Alice").waitForExistence(timeout: 8),
                "Searching from the sidebar found nothing")
            shoot("30-sidebar-search")
            app.sidebarRow("My Feed").tapOrClick()

            // The account menu: collapsed until the current account is
            // clicked, then it holds the pages that are about you.
            let toggle = app.buttons.matching(
                NSPredicate(format: "label CONTAINS 'account menu'")
            ).firstMatch
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), "No account menu toggle")
            XCTAssertFalse(
                app.buttons["Settings"].exists,
                "The account menu was open before anybody asked for it")
            toggle.tapOrClick()
            #if os(iOS)
                let accountItems = ["My profile", "Settings"]
            #else
                let accountItems = [
                    "My profile", "Follow requests", "Liked posts", "Bookmarks", "Blocking",
                    "Settings",
                ]
            #endif
            for item in accountItems {
                XCTAssertTrue(
                    app.buttons[item].waitForExistence(timeout: 4),
                    "\(item) missing from the account menu")
            }
            shoot("29-account-drawer")
            app.buttons["Settings"].tapOrClick()
            XCTAssertTrue(
                app.labelled("Appearance").waitForExistence(timeout: 8),
                "The drawer did not open Settings")

            // Media viewer from Photos.
            app.sidebarRow("Photos").tapOrClick()
            shoot("99-ipad-photos-toolbar")
            print("IPAD PHOTO TOOLBAR:\n\(app.debugDescription)")
            if !app.buttons["Photo layout"].firstMatch.exists {
                let overflow = app.navigationBars.buttons["More"].firstMatch
                if overflow.exists { overflow.tapOrClick() }
            }
            app.buttons["Photo layout"].firstMatch.tapOrClick()
            app.buttons["Grid"].firstMatch.tapOrClick()
            let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'photograph'"))
                .firstMatch
            XCTAssertTrue(tile.waitForExistence(timeout: 8), "No photo tile")
            tile.tapOrClick()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5), "Viewer did not open")
            sleep(2)
            shoot("28-split-viewer")
        }

        func testEverySidebarRowOpensItsScreen() throws {
            #if os(iOS)
                try XCTSkipIf(
                    UIDevice.current.userInterfaceIdiom != .pad, "Sidebar exists on iPad only")
            #endif
            // Rows combine their children for VoiceOver, so match on labels.
            XCTAssertTrue(
                app.labelled("Alice").waitForExistence(timeout: 20), "Home did not render")
            shoot("20-mac-home")

            let expectations: [(row: String, marker: String)] = [
                ("Activities", "Bob favourited your post"),
                ("Direct messages", "Bob"),
                ("Discover", "Discover"),
                ("Your lists", "Colleagues"),
                ("Photos", "Photos"),
                ("Videos", "Videos"),
                ("Shorts", "Unmute"),
                ("My Feed", "My Feed"),
            ]
            for (row, marker) in expectations {
                let cell = app.sidebarRow(row)
                XCTAssertTrue(cell.waitForExistence(timeout: 5), "Sidebar row \(row) missing")
                cell.tapOrClick()
                XCTAssertTrue(
                    app.labelled(marker).waitForExistence(timeout: 8),
                    "\(row) did not show '\(marker)'")
                shoot("21-mac-\(row.lowercased())")
            }
        }
    }
#endif
