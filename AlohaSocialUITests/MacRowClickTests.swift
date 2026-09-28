// SPDX-License-Identifier: MIT

import XCTest

#if os(macOS)
    /// Every part of a timeline row is clickable on the Mac.
    ///
    /// A tour once concluded that clicking a post did nothing on macOS; it had
    /// clicked one point and used an iOS back button. The row's text, its empty
    /// gutter and its avatar are each checked here so that claim can be settled
    /// by running something rather than by reasoning about SwiftUI.
    ///
    /// The split shell has no navigation bar, so returning to the timeline is a
    /// click on the sidebar's Home row rather than a back button.
    /// `@MainActor` because every `XCUIElement` member is: without it each
    /// `tap()` and `waitForExistence` is a nonisolated call into main-actor
    /// state, which is a warning per line and a build failure once warnings
    /// are errors (docs/12 §6).
    @MainActor
    final class MacRowClickTests: XCTestCase {
        func testWhereRowClicksLand() {
            let app = XCUIApplication()
            app.launchArguments = ["-AlohaMockServer"]
            app.launch()
            XCTAssertTrue(app.labelled("Test post number 1").waitForExistence(timeout: 20))

            func clickRow(_ dx: Double, _ dy: Double) {
                app.labelled("Test post number 1")
                    .coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).click()
            }
            func backHome() {
                app.sidebarRow("My Feed").click()
                _ = app.labelled("Test post number 1").waitForExistence(timeout: 5)
            }

            clickRow(0.02, 0.5)
            XCTAssertTrue(
                app.labelled("Reply 1 to that").waitForExistence(timeout: 4),
                "The empty gutter beside the avatar does not open the post")
            backHome()

            clickRow(0.3, 0.06)
            XCTAssertTrue(
                app.labelled("Reply 1 to that").waitForExistence(timeout: 4),
                "The body text does not open the post")
            backHome()

            clickRow(0.035, 0.05)
            XCTAssertTrue(
                app.labelled("Followers").waitForExistence(timeout: 4),
                "The avatar does not open the profile")
        }
    }
#endif
