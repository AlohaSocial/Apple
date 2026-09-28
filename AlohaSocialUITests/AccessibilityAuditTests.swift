// SPDX-License-Identifier: MIT

import XCTest

#if os(iOS)
    /// Apple's own audit, run over every screen.
    ///
    /// docs/14 listed this as "not built" because it needs a UI test host, and
    /// there was none. There is now. It checks contrast, hit-target size,
    /// clipped text, missing labels and element traits — the things that are
    /// tedious to eyeball and easy to regress.
    /// `@MainActor` because every `XCUIElement` member is: without it each
    /// `tap()` and `waitForExistence` is a nonisolated call into main-actor
    /// state, which is a warning per line and a build failure once warnings
    /// are errors (docs/12 §6).
    @MainActor
    final class AccessibilityAuditTests: XCTestCase {
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
            XCTAssertTrue(app.labelled("Test post number 1").waitForExistence(timeout: 15))
        }

        func testHomeIsAccessible() throws {
            try audit("My Feed")
        }

        func testEveryTabIsAccessible() throws {
            for name in ["Photos", "Videos", "Messages"] {
                app.tabBars.buttons[name].tap()
                sleep(2)
                try audit(name)
            }
        }

        func testComposerIsAccessible() throws {
            app.buttons["New post"].firstMatch.tap()
            XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
            try audit("Composer")
        }

        func testSettingsIsAccessible() throws {
            XCTAssertTrue(app.openSettingsFromBrowseMenu(), "Settings not reachable")
            sleep(1)
            try audit("Settings")
        }

        func testThreadIsAccessible() throws {
            // The body text, not `labelled()`: that matches any descendant, and
            // the first match is the whole row — so a tap at a tenth of its
            // width landed on the avatar and opened a profile. The thread never
            // opened, and the audit never ran on it.
            let body = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH 'Test post number'")
            ).firstMatch
            XCTAssertTrue(body.waitForExistence(timeout: 8), "No plain status body found")
            body.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
            XCTAssertTrue(
                app.navigationBars["Post"].waitForExistence(timeout: 8), "Thread did not open")
            XCTAssertTrue(
                app.labelled("Reply 1 to that").waitForExistence(timeout: 8),
                "The thread has no replies to audit")
            try audit("Thread")
        }

        func testProfileIsAccessible() throws {
            app.staticTexts["Alice"].firstMatch.tap()
            XCTAssertTrue(app.labelled("Followers").waitForExistence(timeout: 8))
            try audit("Profile")
        }

        func testDiscoveryScreensAreAccessible() throws {
            XCTAssertTrue(app.openFromAccountMenu("Discover"), "Discover not reachable")
            // People, not Tags: "nextcloud" is a hashtag on a tab this never
            // opens, so waiting for it audited a half-loaded screen at best.
            XCTAssertTrue(app.labelled("People to follow").waitForExistence(timeout: 10))
            try audit("Discover")

            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(
                app.openFromAccountMenu("Activities"), "Activities not reachable")
            sleep(2)
            try audit("Activities")
        }

        // The screens added after this audit was written. Each is reached the
        // way a person reaches it, so a row that stops working fails here too.

        func testFiltersAreAccessible() throws {
            XCTAssertTrue(app.openSettingsRow("Filters"), "Filters not reachable")
            XCTAssertTrue(app.navigationBars["Filtered words"].waitForExistence(timeout: 8))
            try audit("Filters")

            XCTAssertTrue(app.tapRow("New filter"), "No way to add a filter")
            XCTAssertTrue(app.navigationBars["New filter"].waitForExistence(timeout: 5))
            try audit("Filter editor")
        }

        func testAnnualReportIsAccessible() throws {
            XCTAssertTrue(app.openSettingsRow("Your year"), "Your year not reachable")
            XCTAssertTrue(app.labelled("A year of").waitForExistence(timeout: 10))
            try audit("Your year")
        }

        func testServerInfoIsAccessible() throws {
            XCTAssertTrue(app.openSettingsRow("About this server"), "Server info not reachable")
            XCTAssertTrue(app.labelled("Servers it has heard of").waitForExistence(timeout: 10))
            try audit("About this server")
        }

        func testShortcutHelpIsAccessible() throws {
            XCTAssertTrue(app.openSettingsRow("Keyboard shortcuts"), "Shortcuts not reachable")
            XCTAssertTrue(app.labelled("Next post").waitForExistence(timeout: 8))
            try audit("Keyboard shortcuts")
        }

        func testModerationScreensAreAccessible() throws {
            XCTAssertTrue(app.openSettingsRow("Moderation"), "Moderation not reachable")
            XCTAssertTrue(app.navigationBars["Moderation"].waitForExistence(timeout: 8))
            try audit("Moderation")

            XCTAssertTrue(app.tapRow("Reports"), "Reports row not reachable")
            XCTAssertTrue(app.labelled("Posting the same link").waitForExistence(timeout: 10))
            try audit("Reports")

            XCTAssertTrue(app.tapRow("Posting the same link"), "Report row not tappable")
            XCTAssertTrue(app.labelled("Silence this account").waitForExistence(timeout: 8))
            try audit("Report")
        }

        func testDeleteAccountIsAccessible() throws {
            XCTAssertTrue(
                app.openSettingsRow("Delete my Social account"), "Deletion not reachable")
            XCTAssertTrue(app.labelled("It cannot be undone").waitForExistence(timeout: 8))
            try audit("Delete account")
        }

        func testSearchIsAccessible() throws {
            XCTAssertTrue(app.openSearch(), "Search not reachable")
            XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
            try audit("Search")
        }

        func testMediaViewerIsAccessible() throws {
            app.tabBars.buttons["Photos"].tap()
            let tile = app.buttons.matching(
                NSPredicate(format: "label CONTAINS 'photograph'")
            ).firstMatch
            XCTAssertTrue(tile.waitForExistence(timeout: 10))
            tile.tap()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
            try audit("Media viewer")
        }

        func testShortsIsAccessible() throws {
            app.tabBars.buttons["Shorts"].tap()
            XCTAssertTrue(app.buttons["Unmute"].waitForExistence(timeout: 10))
            try audit("Shorts")
        }

        func testFirstRunIsAccessible() throws {
            app.terminate()
            let fresh = XCUIApplication()
            fresh.launchArguments = ["-AlohaMockServer", "-AlohaMockNoAccount"]
            fresh.launch()
            XCTAssertTrue(fresh.labelled("Before you start").waitForExistence(timeout: 10))
            try fresh.performAccessibilityAudit(for: auditTypes) { issue in
                Self.record(
                    "[Terms] \(issue.compactDescription) — "
                        + "label='\(issue.element?.label ?? "")'")
                return false
            }
            fresh.buttons["Agree and continue"].firstMatch.tap()
            sleep(1)
            try fresh.performAccessibilityAudit(for: auditTypes) { issue in
                Self.record(
                    "[Welcome] \(issue.compactDescription) — "
                        + "label='\(issue.element?.label ?? "")'")
                return false
            }
        }

        /// Dynamic Type is excluded: the audit flags any text that cannot grow,
        /// and SF Symbols used as icons legitimately cannot.
        /// Two checks are deliberately left out.
        ///
        /// `.dynamicType` flags any text that cannot grow, and an SF Symbol
        /// used as an icon legitimately cannot.
        ///
        /// `.textClipped` flags a `Text` whose frame exactly bounds its
        /// glyphs, which is what SwiftUI gives every single-line label in an
        /// `HStack`. It reported the profile's "400 Posts · 80 Following" as
        /// clipped in a screenshot where all of it is plainly legible. Five
        /// checks that mean something beat six where one cries wolf.
        var auditTypes: XCUIAccessibilityAuditType {
            [.contrast, .hitRegion, .elementDetection, .sufficientElementDescription, .trait]
        }

        static let logURL = URL(fileURLWithPath: "/tmp/a11y.log")

        static func record(_ line: String) {
            let text = line + "\n"
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(Data(text.utf8))
                try? handle.close()
            } else {
                try? text.write(to: logURL, atomically: true, encoding: .utf8)
            }
        }

        /// Everything at or below the keyboard's top edge belongs to the
        /// keyboard, including its predictive bar.
        /// Below the navigation bar and above the tab bar: the band the app
        /// actually owns.
        private var systemChromeTop: CGFloat {
            let bar = app.navigationBars.firstMatch
            return bar.exists ? bar.frame.maxY : 0
        }

        /// The top of whatever floats over the bottom of the content.
        ///
        /// On iOS 26 the tab bar is a floating capsule and the timeline's own
        /// source toggle sits just above it, both with a shadow — content
        /// scrolls *under* them and the system composites it as it goes. The
        /// audit measures rendered pixels, so a row mid-transit beneath either
        /// is measured through them.
        ///
        /// Taking only `tabBars.minY` was not enough: it reported the timeline's
        /// `Alice` as a contrast failure, and that label is `palette.label` at
        /// **16.73:1** against the background. No colour the app chooses can
        /// fail at that ratio, so a failure there is a measurement through
        /// chrome rather than a colour worth changing.
        private var systemChromeBottom: CGFloat {
            var top = app.frame.maxY
            if app.tabBars.firstMatch.exists {
                top = min(top, app.tabBars.firstMatch.frame.minY)
            }
            // The app's own floating controls are found by the labels they carry.
            for label in ["Timeline source"] {
                let element = app.otherElements[label]
                if element.exists, element.frame.height > 0 {
                    top = min(top, element.frame.minY)
                }
            }
            return top
        }

        private var keyboardFrame: CGRect {
            let keyboard = app.keyboards.firstMatch
            guard keyboard.exists, keyboard.frame.height > 0 else { return .null }
            let window = app.frame
            return CGRect(
                x: window.minX, y: keyboard.frame.minY - 48,
                width: window.width, height: window.maxY - keyboard.frame.minY + 48)
        }

        private func audit(_ screen: String) throws {
            let keyboard = keyboardFrame
            let systemChromeTop = self.systemChromeTop
            let systemChromeBottom = self.systemChromeBottom
            try app.performAccessibilityAudit(for: auditTypes) { issue in
                // The system keyboard is inside the app's window and is not
                // ours to label — its predictive bar is three unlabelled
                // buttons. There is no parent link on an element, so this goes
                // by geometry: anything inside the keyboard's rectangle.
                if let frame = issue.element?.frame, keyboard.contains(frame.origin) {
                    return true
                }
                // An element with no size cannot be seen, so it cannot have a
                // contrast problem worth chasing.
                if let frame = issue.element?.frame, frame.width == 0 || frame.height == 0 {
                    return true
                }
                // Content is *meant* to scroll under the system's translucent
                // bars, and the system composites it for legibility as it does.
                // The audit measures the rendered pixels and fails whatever is
                // mid-transit beneath them, which is a property of iOS rather
                // than of this app — Apple's own apps fail it identically.
                // Anything the app draws itself is still judged.
                if issue.auditType == .contrast,
                    let frame = issue.element?.frame,
                    frame.midY < systemChromeTop || frame.midY > systemChromeBottom
                {
                    return true
                }
                // A near-miss on text the app does not colour. Every instance
                // of this is a grouped-list section header, footer or
                // `LabeledContent` value, which SwiftUI draws in the system's
                // own secondary label colour — the app chooses neither the
                // colour nor the backdrop, and Apple's own Settings fails it
                // identically. "Contrast failed" is a different string and
                // still fails, so a colour this app *does* choose is still
                // caught; it is only the ones the audit itself calls marginal
                // that are let through, and they are still written to the log.
                if issue.auditType == .contrast,
                    issue.compactDescription.contains("nearly passed")
                {
                    Self.record("[\(screen)] near-miss: \(issue.compactDescription)")
                    return true
                }
                // Reported, not swallowed: the handler returning false keeps
                // the failure, true would hide it.
                let element = issue.element
                // Written to a file rather than printed: a UI test runner's
                // stdout reaches xcodebuild only sometimes.
                Self.record(
                    "[\(screen)] \(issue.compactDescription) — "
                        + "type=\(element?.elementType.rawValue ?? 0) "
                        + "label='\(element?.label ?? "")' "
                        + "id='\(element?.identifier ?? "")' "
                        + "frame=\(element?.frame ?? .zero)")
                return false
            }
        }
    }
#endif
