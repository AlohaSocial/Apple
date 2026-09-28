// SPDX-License-Identifier: MIT

import XCTest

#if os(iOS)

    /// Drives the app against the mock server and photographs every screen.
    ///
    /// This exists because reading code found fourteen bugs and missed the four
    /// that were visible in the first screenshot. Each test asserts the elements a
    /// screen must have, and saves a PNG to `/tmp/shots/` — the simulator shares
    /// the host filesystem — so a person can look at it.
    /// `@MainActor` because every `XCUIElement` member is: without it each
    /// `tap()` and `waitForExistence` is a nonisolated call into main-actor
    /// state, which is a warning per line and a build failure once warnings
    /// are errors (docs/12 §6).
    @MainActor
    final class ScreenTourTests: XCTestCase {
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
            app.dismissSystemAlertsIfPresent()
        }

        // MARK: - Screens

        func testHomeTimelineRenders() {
            XCTAssertTrue(
                app.staticTexts["My Feed"].waitForExistence(timeout: 10), "My Feed title missing")
            XCTAssertTrue(
                app.staticTexts["Alice"].firstMatch.waitForExistence(timeout: 10),
                "No status row rendered — the timeline did not load from the mock")
            shoot("10-home")
        }

        func testEveryTabOpens() {
            XCTAssertTrue(app.staticTexts["My Feed"].waitForExistence(timeout: 10))
            for name in ["Photos", "Videos", "Shorts", "Messages"] {
                let tab = app.tabBars.buttons[name]
                XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(name) tab missing")
                tab.tap()
                sleep(2)
                shoot("11-tab-\(name.lowercased())")
            }
        }

        func testThreadOpensFromRow() {
            XCTAssertTrue(app.staticTexts["Alice"].firstMatch.waitForExistence(timeout: 10))
            // Tap the body of the second row, which has no content warning.
            let body = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH 'Test post number'")
            ).firstMatch
            XCTAssertTrue(body.waitForExistence(timeout: 5), "No plain status body found")
            // Left edge of the text, well away from the trailing link.
            body.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
            XCTAssertTrue(
                app.navigationBars["Post"].waitForExistence(timeout: 5), "Thread did not open")
            shoot("12-thread")
        }

        func testComposerOpens() {
            XCTAssertTrue(app.staticTexts["My Feed"].waitForExistence(timeout: 10))
            let compose = app.buttons["New post"].firstMatch
            XCTAssertTrue(compose.waitForExistence(timeout: 5), "Compose button missing")
            compose.tap()
            XCTAssertTrue(
                app.navigationBars["New post"].waitForExistence(timeout: 5), "Composer did not open"
            )
            shoot("13-composer")
            app.buttons["Cancel"].firstMatch.tap()
        }

        func testSettingsOpens() {
            XCTAssertTrue(app.staticTexts["My Feed"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.openSettingsFromBrowseMenu(), "Settings not reachable from Browse")
            XCTAssertTrue(
                app.navigationBars["Settings"].waitForExistence(timeout: 5), "Settings did not open"
            )
            shoot("14-settings")
        }

        func testNotificationsListRenders() {
            XCTAssertTrue(app.staticTexts["My Feed"].waitForExistence(timeout: 10))
            XCTAssertTrue(
                app.openFromAccountMenu("Activities"), "Activities missing from the account menu")
            XCTAssertTrue(
                app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Bob '")).firstMatch
                    .waitForExistence(timeout: 10),
                "No notification rendered from the mock")
            shoot("17-notifications")
        }

        func testShortsRendersOverlay() {
            XCTAssertTrue(app.staticTexts["My Feed"].waitForExistence(timeout: 10))
            app.tabBars.buttons["Shorts"].tap()
            XCTAssertTrue(
                app.buttons["Unmute"].waitForExistence(timeout: 10), "Shorts overlay missing")
            sleep(1)
            shoot("18-shorts")
        }

        func testSearchOpens() {
            XCTAssertTrue(app.staticTexts["My Feed"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.openSearch(), "No search button in the toolbar")
            XCTAssertTrue(
                app.searchFields.firstMatch.waitForExistence(timeout: 5), "No search field")
            sleep(1)
            shoot("19-search")
        }

        func testContentWarningExpands() {
            let warning = app.staticTexts["Testing"].firstMatch
            XCTAssertTrue(warning.waitForExistence(timeout: 10), "Content warning row missing")
            warning.tap()
            sleep(1)
            shoot("15-cw-expanded")
        }

        func testProfileOpensFromAvatar() {
            XCTAssertTrue(app.staticTexts["Alice"].firstMatch.waitForExistence(timeout: 10))
            app.staticTexts["Alice"].firstMatch.tap()
            // Your own profile has no Follow button, so the stats line is the tell.
            let stats = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Followers'")
            ).firstMatch
            XCTAssertTrue(stats.waitForExistence(timeout: 5), "Profile did not open")
            sleep(2)
            shoot("16-profile")
        }

    }
#endif
