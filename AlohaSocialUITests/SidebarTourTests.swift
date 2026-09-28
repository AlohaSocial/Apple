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
            #if os(iOS)
                try XCTSkipIf(
                    UIDevice.current.userInterfaceIdiom != .pad, "Sidebar exists on iPad only")
            #endif
            XCTAssertTrue(app.labelled("Alice").waitForExistence(timeout: 20))

            // Thread from a row body.
            let body = app.labelled("Test post number 1 with")
            XCTAssertTrue(body.waitForExistence(timeout: 5))
            body.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.06)).tapOrClick()
            XCTAssertTrue(
                app.labelled("Reply 1 to that").waitForExistence(timeout: 8), "Thread did not open")
            shoot("22-split-thread")

            // Profile from the avatar in the focused post.
            app.labelled("Test post number 1 with")
                .coordinate(withNormalizedOffset: CGVector(dx: 0.035, dy: 0.05)).tapOrClick()
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
                app.labelled("photography").waitForExistence(timeout: 8), "Explore has no trends")
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
            let field = app.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5), "No search field in the sidebar")
            field.tapOrClick()
            field.typeText("alice\n")
            XCTAssertTrue(
                app.labelled("Alice").waitForExistence(timeout: 8),
                "Searching from the sidebar found nothing")
            shoot("30-sidebar-search")
            app.sidebarRow("My Feed").tapOrClick()

            // The account drawer: collapsed until the current account is
            // clicked, then it holds the pages that are about you.
            let toggle = app.buttons.matching(
                NSPredicate(format: "label CONTAINS 'account menu'")
            ).firstMatch
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), "No account drawer toggle")
            XCTAssertFalse(
                app.buttons["Settings"].exists,
                "The account drawer was open before anybody asked for it")
            toggle.tapOrClick()
            for item in [
                "My profile", "Follow requests", "Liked posts", "Bookmarks",
                "Blocking", "Settings",
            ] {
                XCTAssertTrue(
                    app.buttons[item].waitForExistence(timeout: 4),
                    "\(item) missing from the account drawer")
            }
            shoot("29-account-drawer")
            app.buttons["Settings"].tapOrClick()
            XCTAssertTrue(
                app.labelled("Appearance").waitForExistence(timeout: 8),
                "The drawer did not open Settings")

            // Media viewer from Photos.
            app.sidebarRow("Photos").tapOrClick()
            let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'photograph'"))
                .firstMatch
            XCTAssertTrue(tile.waitForExistence(timeout: 8), "No photo tile")
            tile.tapOrClick()
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

        /// Activities moved out of the sidebar and into the account drawer,
        /// under My profile: the sidebar is feeds, and this is about you.
        func testActivitiesLivesInTheAccountDrawer() throws {
            #if os(iOS)
                try XCTSkipIf(
                    UIDevice.current.userInterfaceIdiom != .pad, "Sidebar exists on iPad only")
            #endif
            XCTAssertTrue(
                app.labelled("Alice").waitForExistence(timeout: 20), "Home did not render")

            XCTAssertNil(
                app.sidebarRow("Activities").exists ? true : nil,
                "Activities is still a sidebar row")

            let toggle = app.buttons.matching(
                NSPredicate(format: "label CONTAINS 'account menu'")
            ).firstMatch
            XCTAssertTrue(toggle.waitForExistence(timeout: 8), "No account drawer toggle")
            toggle.tapOrClick()

            let activities = app.labelled("Activities")
            XCTAssertTrue(
                activities.waitForExistence(timeout: 5), "Activities missing from the drawer")
            activities.tapOrClick()
            XCTAssertTrue(
                app.labelled("Bob favourited your post").waitForExistence(timeout: 8),
                "Activities did not open from the drawer")
            shoot("29-drawer-activities")
        }
    }
#endif
