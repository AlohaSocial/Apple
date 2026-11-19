// SPDX-License-Identifier: MIT
import XCTest

#if os(iOS)
    import UIKit

    /// Reading on iPhone and iPad: the reply bar at the foot of a thread, the
    /// detail column on a 13-inch iPad upright, and the sidebar's folded
    /// "More" section.
    @MainActor
    final class ReadingTourTests: XCTestCase {
        private let app = XCUIApplication()

        override func setUp() async throws {
            continueAfterFailure = false
            XCUIDevice.shared.orientation = .portrait
            app.launchArguments = ["-AlohaMockServer"]
            app.launch()
            app.dismissSystemAlertsIfPresent()
        }

        override func tearDown() async throws {
            XCUIDevice.shared.orientation = .portrait
        }

        private func openFirstPost() {
            let body = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH 'Test post number'")
            ).firstMatch
            XCTAssertTrue(body.waitForExistence(timeout: 20), "No plain status body found")
            body.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
            XCTAssertTrue(app.navigationBars["Post"].waitForExistence(timeout: 8), "No thread")
        }

        func testReplyBarSendsAndExpands() throws {
            openFirstPost()
            let field = app.descendants(matching: .any)
                .matching(identifier: "quickReply.field").firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5), "No reply bar in the thread")
            XCTAssertFalse(app.buttons["quickReply.send"].isEnabled, "Send enabled while empty")
            field.tap()
            field.typeText("Nice one")
            XCTAssertTrue(app.buttons["quickReply.send"].isEnabled)
            shoot("reading-reply-bar")

            // The words go to the full composer. (The mock's first post is
            // the reader's own, so there is nobody to address.)
            app.buttons["Open in the composer"].firstMatch.tap()
            let typed = app.descendants(matching: .any).matching(
                NSPredicate(format: "value CONTAINS 'Nice one'")
            ).firstMatch
            XCTAssertTrue(
                typed.waitForExistence(timeout: 8), "The composer did not open on the words")
            shoot("reading-reply-expanded")
        }

        func testLargeIPadUprightOpensPostsBesideTheList() throws {
            try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad only")
            try XCTSkipIf(app.windows.firstMatch.frame.width < 1000, "Narrower than a 13-inch")
            openFirstPost()
            XCTAssertTrue(
                app.buttons["Close"].firstMatch.waitForExistence(timeout: 5),
                "No detail column on a 13-inch iPad upright")
            shoot("reading-ipad-portrait-detail-column")
        }

        func testSidebarFoldsTheLongTail() throws {
            try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad only")
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(app.sidebarRow("My Feed").waitForExistence(timeout: 20))
            XCTAssertTrue(app.sidebarRow("Discover").exists)
            XCTAssertFalse(app.sidebarRow("Blocking").exists, "The long tail is not folded")
            shoot("reading-sidebar-folded")
            app.expandSidebarMore()
            XCTAssertTrue(app.sidebarRow("Your lists").waitForExistence(timeout: 5))
            XCTAssertTrue(app.sidebarRow("Settings").exists)
            shoot("reading-sidebar-more")
            app.sidebarRow("Your lists").tap()
            XCTAssertTrue(app.labelled("Colleagues").waitForExistence(timeout: 8))
        }
    }
#endif
