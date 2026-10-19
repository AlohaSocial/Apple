// SPDX-License-Identifier: MIT

import XCTest

#if os(iOS)
    /// The pseudolanguages docs/12 §4 asks for, as a screenshot run.
    ///
    /// No language but English and German ships, so truncation and hard-coded
    /// direction only show up when something forces them: the double-length
    /// pseudolanguage makes every localised string twice as long (German runs
    /// about a third longer than English, Finnish more), the accented one marks
    /// every string that went through the catalog — anything still plain was
    /// never localised — and the right-to-left one mirrors the layout. These
    /// are the system's own switches, the ones Xcode's scheme options set.
    ///
    /// The checks are deliberately few: that the tab bar and a post are still
    /// reachable. The screenshots, kept as attachments and in `/tmp/shots`,
    /// are what a person reviews.
    @MainActor
    final class PseudolocalisationTourTests: XCTestCase {
        private func launch(_ extra: [String]) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-AlohaMockServer"] + extra
            app.launch()
            app.dismissSystemAlertsIfPresent()
            return app
        }

        /// Twice the length, and every catalogued string bracketed and
        /// accented — the en-XA run.
        func testDoubleLengthAccented() {
            let app = launch([
                "-NSDoubleLocalizedStrings", "YES",
                "-NSAccentuateLocalizedStrings", "YES",
                "-NSSurroundLocalizedStrings", "YES",
            ])
            // Post text is the server's, so it is not pseudolocalised: it is
            // the one thing that can still be found by its words.
            XCTAssertTrue(app.labelled("Test post").waitForExistence(timeout: 20))
            XCTAssertTrue(app.tabBars.firstMatch.exists, "The tab bar is gone at double length")
            shoot("70-pseudo-double-home")

            app.tabBars.buttons.element(boundBy: 1).tap()
            sleep(1)
            shoot("71-pseudo-double-second-tab")

            app.tabBars.buttons.element(boundBy: 0).tap()
            app.labelled("Test post number 1").firstMatch.tap()
            sleep(1)
            shoot("72-pseudo-double-thread")
        }

        /// The right-to-left pseudolanguage — the ar-XB run: the layout
        /// mirrors while the strings stay readable English.
        func testRightToLeftPseudolanguage() {
            let app = launch([
                "-AppleTextDirection", "YES",
                "-NSForceRightToLeftWritingDirection", "YES",
            ])
            XCTAssertTrue(app.labelled("Test post").waitForExistence(timeout: 20))
            XCTAssertTrue(app.tabBars.firstMatch.exists)
            shoot("73-pseudo-rtl-home")

            app.labelled("Test post number 1").firstMatch.tap()
            sleep(1)
            shoot("74-pseudo-rtl-thread")
        }
    }
#endif
