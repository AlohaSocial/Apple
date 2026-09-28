// SPDX-License-Identifier: MIT

import XCTest

#if os(iOS)

    /// The screens added after the first tour was written: keyword filters,
    /// "Your year", about-this-server, the moderator's three, the follow
    /// constellation, the composer's card row and the shortcut sheet.
    ///
    /// A screen nobody drives is a screen the accessibility audit never sees
    /// and the screenshots never show, which is how the first pass shipped a
    /// route pointing at a view that did not exist.
    /// `@MainActor` because every `XCUIElement` member is: without it each
    /// `tap()` and `waitForExistence` is a nonisolated call into main-actor
    /// state, which is a warning per line and a build failure once warnings
    /// are errors (docs/12 §6).
    @MainActor
    final class AddedScreensTourTests: XCTestCase {
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
            XCTAssertTrue(app.staticTexts["My Feed"].waitForExistence(timeout: 15))
        }

        // MARK: - Settings surfaces

        func testFiltersOpenAndEdit() {
            XCTAssertTrue(app.openSettingsRow("Filters"), "Filters not reachable from Settings")
            XCTAssertTrue(
                app.navigationBars["Filtered words"].waitForExistence(timeout: 8),
                "Filters screen did not open")
            shoot("30-filters")

            let add = app.labelled("New filter")
            XCTAssertTrue(add.waitForExistence(timeout: 5), "No way to add a filter")
            add.tap()
            XCTAssertTrue(
                app.navigationBars["New filter"].waitForExistence(timeout: 5),
                "Filter editor did not open")
            shoot("31-filter-editor")
            app.buttons["Cancel"].firstMatch.tap()
        }

        func testAnnualReportOpens() {
            XCTAssertTrue(app.openSettingsRow("Your year"), "Your year not reachable")
            XCTAssertTrue(
                app.navigationBars["Your year"].waitForExistence(timeout: 8),
                "Annual report did not open")
            // The mock always serves last year's report, so the archetype line
            // is the tell that it decoded rather than fell back to the empty
            // state.
            XCTAssertTrue(
                app.labelled("A year of").waitForExistence(timeout: 8),
                "No archetype line — the report did not decode")
            shoot("32-your-year")
        }

        func testServerInfoOpens() {
            XCTAssertTrue(app.openSettingsRow("About this server"), "Server info not reachable")
            XCTAssertTrue(
                app.navigationBars["About this server"].waitForExistence(timeout: 8),
                "Server info did not open")
            XCTAssertTrue(
                app.labelled("Servers it has heard of").waitForExistence(timeout: 8),
                "Peer count missing")
            shoot("33-server-info")
        }

        func testShortcutHelpOpens() {
            XCTAssertTrue(app.openSettingsRow("Keyboard shortcuts"), "Shortcuts not reachable")
            XCTAssertTrue(
                app.navigationBars["Keyboard shortcuts"].waitForExistence(timeout: 8),
                "Shortcut sheet did not open")
            XCTAssertTrue(
                app.labelled("Next post").waitForExistence(timeout: 5),
                "The shortcut list is empty")
            shoot("34-shortcuts")
            app.buttons["Done"].firstMatch.tap()
        }

        func testDeleteAccountScreenWarnsBeforeItOffers() {
            XCTAssertTrue(
                app.openSettingsRow("Delete my Social account"), "Deletion not reachable")
            XCTAssertTrue(
                app.navigationBars["Delete account"].waitForExistence(timeout: 8),
                "Delete account screen did not open")
            XCTAssertTrue(
                app.labelled("It cannot be undone").waitForExistence(timeout: 5),
                "The screen offers deletion without saying it is permanent")
            shoot("35-delete-account")
        }

        // MARK: - Moderation

        func testModerationScreens() {
            XCTAssertTrue(app.openSettingsRow("Moderation"), "Moderation not reachable")
            XCTAssertTrue(
                app.navigationBars["Moderation"].waitForExistence(timeout: 8),
                "Moderation hub did not open")
            shoot("36-moderation")

            XCTAssertTrue(app.tapRow("Reports"), "Reports row not reachable")
            XCTAssertTrue(
                app.navigationBars["Reports"].waitForExistence(timeout: 8),
                "Reports queue did not open")
            XCTAssertTrue(
                app.labelled("Posting the same link").waitForExistence(timeout: 8),
                "No report rendered from the mock")
            shoot("37-reports")

            XCTAssertTrue(
                app.tapRow("Posting the same link"), "The report row is not tappable")
            XCTAssertTrue(
                app.navigationBars["Report"].waitForExistence(timeout: 8),
                "One report did not open")
            XCTAssertTrue(
                app.labelled("Silence this account").waitForExistence(timeout: 5),
                "No decision offered on a report")
            shoot("38-report")
        }

        func testModerationAccountsAndTrends() {
            XCTAssertTrue(app.openSettingsRow("Moderation"), "Moderation not reachable")
            XCTAssertTrue(app.navigationBars["Moderation"].waitForExistence(timeout: 8))

            XCTAssertTrue(app.tapRow("Accounts"), "Accounts row not reachable")
            XCTAssertTrue(
                app.navigationBars["Accounts"].waitForExistence(timeout: 8),
                "Moderation accounts did not open")
            XCTAssertTrue(
                app.labelled("Suspended").waitForExistence(timeout: 8),
                "No standing badge — the admin accounts did not decode")
            shoot("39-moderation-accounts")

            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.tapRow("What may trend"), "Trends row not reachable")
            XCTAssertTrue(
                app.navigationBars["What may trend"].waitForExistence(timeout: 8),
                "Trend review did not open")
            XCTAssertTrue(
                app.labelled("Keep it out").waitForExistence(timeout: 8),
                "No trend decision offered")
            shoot("40-trends")
        }

        // MARK: - Discover and the composer

        func testConstellationDraws() {
            XCTAssertTrue(app.openFromAccountMenu("Discover"), "Discover not reachable")
            let toggle = app.switches.containing(
                NSPredicate(format: "label CONTAINS 'constellation'")
            ).firstMatch
            guard app.scrollTo(toggle, in: app.collectionViews.firstMatch) || toggle.exists else {
                // The graph only appears where the server answered with
                // suggestions; without them there is nothing to draw and no
                // switch, which is correct rather than a failure.
                shoot("41-discover-no-graph")
                return
            }
            toggle.tap()
            sleep(1)
            shoot("42-constellation")
        }

        func testComposerOffersACardForAShortPost() {
            let compose = app.buttons["New post"].firstMatch
            XCTAssertTrue(compose.waitForExistence(timeout: 8), "Compose button missing")
            compose.tap()
            XCTAssertTrue(app.navigationBars["New post"].waitForExistence(timeout: 5))

            let editor = app.textViews.firstMatch
            XCTAssertTrue(editor.waitForExistence(timeout: 5), "No composer text view")
            editor.tap()
            editor.typeText("Short enough to be a card")

            XCTAssertTrue(
                app.labelled("Post it as a card").waitForExistence(timeout: 5),
                "A short post was not offered as a card")
            shoot("43-composer-card")
            app.buttons["Cancel"].firstMatch.tap()
        }

        func testComposerHintsAtAGame() {
            app.buttons["New post"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["New post"].waitForExistence(timeout: 5))
            let editor = app.textViews.firstMatch
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            editor.tap()
            editor.typeText("pizza or pasta /dice")

            XCTAssertTrue(
                app.labelled("Rolled when this goes out").waitForExistence(timeout: 5),
                "No hint that the post has a game to play")
            shoot("44-composer-game")
            app.buttons["Cancel"].firstMatch.tap()
        }
    }
#endif
