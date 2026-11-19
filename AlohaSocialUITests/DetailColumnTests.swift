// SPDX-License-Identifier: MIT
import XCTest

#if os(iOS)
    import UIKit

    /// The iPad's detail column: in a wide window a post opens beside the
    /// timeline rather than over it, and turning a smaller iPad upright shows
    /// the same post pushed instead.
    @MainActor
    final class DetailColumnTests: XCTestCase {
        override func tearDown() async throws {
            XCUIDevice.shared.orientation = .portrait
        }

        func testPostOpensBesideTheTimeline() throws {
            try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad only")
            continueAfterFailure = false
            XCUIDevice.shared.orientation = .landscapeLeft
            let app = XCUIApplication()
            app.launchArguments = ["-AlohaMockServer"]
            app.launch()
            app.dismissSystemAlertsIfPresent()

            let body = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH 'Test post number'")
            ).firstMatch
            XCTAssertTrue(body.waitForExistence(timeout: 20), "No plain status body found")
            let bodyFrame = body.frame
            body.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()

            // The thread is in a column of its own, and the timeline is still
            // on screen beside it.
            let close = app.buttons["Close"].firstMatch
            XCTAssertTrue(close.waitForExistence(timeout: 5), "No detail column opened")
            XCTAssertTrue(app.navigationBars["Post"].waitForExistence(timeout: 5))
            XCTAssertTrue(body.isHittable, "The timeline was pushed away")
            XCTAssertGreaterThan(
                close.frame.minX, bodyFrame.minX, "The detail column is not to the trailing side")
            shoot("97-detail-column-thread")

            // Upright, an iPad under 1000 points wide is too narrow for two
            // columns: the same post is shown pushed, with Back to the
            // timeline. A 13-inch upright (1032) keeps the column.
            XCUIDevice.shared.orientation = .portrait
            XCTAssertTrue(app.navigationBars["Post"].waitForExistence(timeout: 5))
            if app.windows.firstMatch.frame.width < 1000 {
                XCTAssertFalse(app.buttons["Close"].exists, "A detail column in a narrow window")
            } else {
                XCTAssertTrue(
                    app.buttons["Close"].firstMatch.waitForExistence(timeout: 5),
                    "No detail column on a 13-inch iPad upright")
            }
            shoot("97-detail-column-portrait")

            // Nothing was changed while upright, so turning back finds the
            // post in its column again.
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(app.buttons["Close"].firstMatch.waitForExistence(timeout: 5))
            app.buttons["Close"].firstMatch.tap()
            XCTAssertFalse(app.navigationBars["Post"].waitForExistence(timeout: 2))
        }
    }
#endif
