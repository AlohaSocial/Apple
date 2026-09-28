// SPDX-License-Identifier: MIT

import XCTest

#if os(iOS)
    /// Every theme, photographed.
    ///
    /// Five of the six had never been looked at, and the tokens behind them
    /// were changed to meet WCAG AA — exactly the sort of change that looks
    /// right in one palette and wrong in another.
    /// `@MainActor` because every `XCUIElement` member is: without it each
    /// `tap()` and `waitForExistence` is a nonisolated call into main-actor
    /// state, which is a warning per line and a build failure once warnings
    /// are errors (docs/12 §6).
    @MainActor
    final class ThemeTourTests: XCTestCase {
        private var app: XCUIApplication!

        // The `async` overrides, not `setUpWithError`/`tearDown`: XCTest
        // declares those nonisolated, so an override of one stays nonisolated
        // even in a `@MainActor` class, and every line here touches
        // `XCUIApplication`, which is main-actor. The async forms adopt the
        // class's isolation instead.
        override func setUp() async throws {
            continueAfterFailure = true
        }

        override func tearDown() async throws {
            XCUIDevice.shared.appearance = .light
        }

        func testEveryThemeRenders() {
            for theme in [
                "Warm Light", "Warm Dark", "High Contrast Light",
                "High Contrast Dark", "Dim", "Black",
            ] {
                launchAndChoose(theme: theme)
                shoot("60-theme-\(theme.lowercased().replacingOccurrences(of: " ", with: "-"))")
                app.terminate()
            }
        }

        /// The system theme has to follow the system, which is the one case a
        /// screenshot of a fixed theme cannot prove.
        func testSystemThemeFollowsTheSystem() {
            XCUIDevice.shared.appearance = .dark
            app = XCUIApplication()
            app.launchArguments = ["-AlohaMockServer"]
            app.launch()
            app.dismissSystemAlertsIfPresent()
            XCTAssertTrue(app.labelled("Test post number 1").waitForExistence(timeout: 15))
            shoot("61-system-dark")
            XCUIDevice.shared.appearance = .light
            sleep(2)
            shoot("62-system-light")
        }

        /// A sheet is not a descendant of the modifier chain it is attached to,
        /// so the theme has to wrap the presentations rather than sit among
        /// them. When it did not, every sheet the shell owns — composer,
        /// sign-in, report, edit, media viewer — fell back to `AlohaDesign`'s
        /// environment default, Warm Light, and the composer opened cream in an
        /// app running Black.
        ///
        /// Both directions, because "always dark" would pass a test that only
        /// looked at Black and is just as wrong.
        func testSheetsWearTheChosenTheme() {
            for (theme, expectation) in [("Black", Brightness.dark), ("Warm Light", .light)] {
                launchAndChoose(theme: theme)

                let composer = app.buttons["New post"].firstMatch
                XCTAssertTrue(composer.waitForExistence(timeout: 8), "\(theme): no compose button")
                composer.tap()
                XCTAssertTrue(
                    app.textViews.firstMatch.waitForExistence(timeout: 8),
                    "\(theme): composer never opened")
                sleep(1)
                shoot("63-composer-\(theme.lowercased().replacingOccurrences(of: " ", with: "-"))")

                // Empty body text, below the navigation bar and well above the
                // keyboard: the composer's own background and nothing else.
                let surface = CGRect(x: 0.30, y: 0.28, width: 0.40, height: 0.12)
                guard let luminance = meanLuminance(of: surface, in: XCUIScreen.main.screenshot())
                else {
                    XCTFail("\(theme): could not sample the composer")
                    return
                }

                switch expectation {
                case .dark:
                    XCTAssertLessThan(
                        luminance, 0.25,
                        "\(theme): the composer is light (\(luminance)) — the sheet lost the theme")
                case .light:
                    XCTAssertGreaterThan(
                        luminance, 0.70,
                        "\(theme): the composer is dark (\(luminance)) — the sheet lost the theme")
                }

                app.terminate()
            }
        }

        private enum Brightness {
            case dark
            case light
        }

        private func launchAndChoose(theme: String) {
            app = XCUIApplication()
            app.launchArguments = ["-AlohaMockServer"]
            app.launch()
            app.dismissSystemAlertsIfPresent()
            XCTAssertTrue(
                app.labelled("Test post number 1").waitForExistence(timeout: 15),
                "\(theme): timeline never arrived")

            XCTAssertTrue(app.openSettingsFromBrowseMenu(), "\(theme): Settings not reachable")
            let picker = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Theme'")
            ).firstMatch
            XCTAssertTrue(picker.waitForExistence(timeout: 5), "\(theme): no theme picker")
            picker.tap()
            let option = app.buttons[theme].firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5), "\(theme): not offered")
            option.tap()
            sleep(1)
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
    }
#endif
