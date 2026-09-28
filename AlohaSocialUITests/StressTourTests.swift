// SPDX-License-Identifier: MIT

import XCTest

#if os(iOS)
    /// The conditions a timeline is most likely to break under: the largest
    /// text, a right-to-left layout, and a long scroll.
    /// `@MainActor` because every `XCUIElement` member is: without it each
    /// `tap()` and `waitForExistence` is a nonisolated call into main-actor
    /// state, which is a warning per line and a build failure once warnings
    /// are errors (docs/12 §6).
    @MainActor
    final class StressTourTests: XCTestCase {
        private func launch(_ extra: [String]) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-AlohaMockServer"] + extra
            app.launch()
            app.dismissSystemAlertsIfPresent()
            return app
        }

        /// AX5 is the largest size anybody can choose. Rows must still be
        /// readable rather than a column of single words.
        func testLargestTextSize() {
            let app = launch([
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ])
            XCTAssertTrue(app.labelled("Test post").waitForExistence(timeout: 20))
            shoot("63-ax5-home")
            app.tabBars.buttons["Messages"].tap()
            sleep(1)
            shoot("64-ax5-messages")
        }

        /// A fediverse client sees Arabic and Hebrew. The layout has to mirror,
        /// and the Latin text inside it must not.
        func testRightToLeftLayout() {
            let app = launch([
                "-AppleTextDirection", "YES",
                "-NSForceRightToLeftWritingDirection", "YES",
                "-AppleLanguages", "(ar)",
            ])
            XCTAssertTrue(app.labelled("Test post").waitForExistence(timeout: 20))
            shoot("65-rtl-home")
            app.tabBars.buttons.element(boundBy: 1).tap()
            sleep(2)
            shoot("66-rtl-photos")
        }

        /// Scrolling a long way, measured. Nothing here asserts a number — the
        /// point is a baseline that a later change can be compared against.
        func testScrollingPerformance() {
            let app = launch([])
            XCTAssertTrue(app.labelled("Test post number 1").waitForExistence(timeout: 20))
            let metrics: [XCTMetric] = [
                XCTOSSignpostMetric.scrollDecelerationMetric,
                XCTCPUMetric(application: app),
                XCTMemoryMetric(application: app),
            ]
            measure(metrics: metrics, options: XCTMeasureOptions.default) {
                app.swipeUp(velocity: .fast)
                app.swipeUp(velocity: .fast)
                app.swipeDown(velocity: .fast)
            }
        }
    }
#endif
