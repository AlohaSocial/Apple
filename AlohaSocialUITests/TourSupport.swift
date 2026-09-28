// SPDX-License-Identifier: MIT

import XCTest

#if canImport(UIKit)
    import UIKit
#endif

#if os(iOS)
    extension XCTestCase {
        /// The mean luminance of a region of the screen, 0 (black) to 1 (white),
        /// where the region is given in fractions of the screen so it does not
        /// have to be restated per device.
        ///
        /// Everything else in these tours asks whether an element exists and is
        /// labelled. Nothing asked what colour it was drawn in, which is how a
        /// composer that had lost the app's theme — cream, in an app running
        /// Black — passed a forty-screen tour and an accessibility audit
        /// without a single failure.
        ///
        /// A region rather than a pixel: the caret, antialiasing and a sheet's
        /// shadow all move individual pixels, and the question is about the
        /// surface. Averaging is done by drawing the crop into a 1×1 context.
        @MainActor
        func meanLuminance(
            of region: CGRect, in screenshot: XCUIScreenshot
        ) -> Double? {
            guard let image = screenshot.image.cgImage else { return nil }
            let size = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
            let crop = CGRect(
                x: region.minX * size.width, y: region.minY * size.height,
                width: region.width * size.width, height: region.height * size.height
            ).integral
            guard crop.width >= 1, crop.height >= 1,
                let sample = image.cropping(to: crop)
            else { return nil }

            var pixel: [UInt8] = [0, 0, 0, 0]
            guard
                let context = CGContext(
                    data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.interpolationQuality = .medium
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))

            // Rec. 709, the weighting `ServerAccent.luminance` uses, so a
            // failure here reads in the same units as the design tokens.
            return 0.2126 * (Double(pixel[0]) / 255) + 0.7152 * (Double(pixel[1]) / 255)
                + 0.0722 * (Double(pixel[2]) / 255)
        }
    }
#endif

/// Shared plumbing for the screen tours.
extension XCTestCase {
    /// Saves a PNG to `/tmp/shots/` (iOS; the simulator shares the host disk)
    /// and attaches it to the result bundle (everywhere — the macOS runner is
    /// sandboxed and cannot write to `/tmp`).
    /// `@MainActor` because `XCUIScreen` and `XCTAttachment` are: every caller
    /// is a main-actor test class, so saying so costs nothing and clears three
    /// isolation warnings that `ui` now treats as errors.
    @MainActor
    func shoot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let directory = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: directory.appending(path: "\(name).png"))
    }
}

extension XCUIApplication {
    /// Any element whose label, title or value contains the text. Rows combine
    /// their children for VoiceOver, so exact static-text matches miss.
    func labelled(_ text: String) -> XCUIElement {
        descendants(matching: .any).matching(
            NSPredicate(
                format: "label CONTAINS %@ OR title CONTAINS %@ OR value CONTAINS %@",
                text, text, text)
        ).firstMatch
    }

    /// A sidebar row on iPad (collection view) or Mac (outline).
    func sidebarRow(_ title: String) -> XCUIElement {
        #if os(macOS)
            return outlines.cells.containing(.staticText, identifier: title).firstMatch
        #else
            return collectionViews.cells.containing(.staticText, identifier: title).firstMatch
        #endif
    }

    #if os(iOS)
        /// Springboard owns the permission and "Open in" dialogs.
        func dismissSystemAlertsIfPresent() {
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            for label in ["Don’t Allow", "Don't Allow", "Cancel", "Allow"] {
                let button = springboard.buttons[label]
                if button.waitForExistence(timeout: 2) {
                    button.tap()
                    break
                }
            }
        }
    #endif
}

extension XCUIElement {
    func tapOrClick() {
        #if os(macOS)
            click()
        #else
            tap()
        #endif
    }
}

extension XCUICoordinate {
    func tapOrClick() {
        #if os(macOS)
            click()
        #else
            tap()
        #endif
    }
}

#if os(iOS)
    extension XCUIApplication {
        /// Everywhere that is not a timeline hangs off the account menu on the
        /// phone, exactly as it hangs off the account drawer on a Mac.
        @discardableResult
        func openFromAccountMenu(_ title: String) -> Bool {
            let menu = buttons.matching(
                NSPredicate(format: "label CONTAINS 'account menu'")
            ).firstMatch
            guard menu.waitForExistence(timeout: 8) else { return false }
            menu.tap()
            let item = buttons[title].firstMatch
            guard item.waitForExistence(timeout: 5) else { return false }
            item.tap()
            return true
        }

        func openSettingsFromBrowseMenu() -> Bool { openFromAccountMenu("Settings") }

        /// Search is a button of its own in the top-right, not a menu item.
        @discardableResult
        func openSearch() -> Bool {
            let button = buttons["Search"].firstMatch
            guard button.waitForExistence(timeout: 8) else { return false }
            button.tap()
            return true
        }

        /// Scrolls a long list until an element is hittable. Settings is taller
        /// than any simulator, so every row below the fold needs this before it
        /// can be tapped.
        ///
        /// The scroller is found rather than assumed: a `Form` on iOS is a
        /// collection view, a `List` may be a table, and only some screens are
        /// a plain scroll view. Looking only for `scrollViews` found nothing on
        /// Settings, and every row below the fold went untapped.
        func scrollTo(
            _ element: XCUIElement, in scroller: XCUIElement? = nil, swipes: Int = 15
        ) -> Bool {
            let view = scroller ?? firstScroller
            for _ in 0..<swipes {
                if element.exists, element.isHittable { return true }
                view.swipeUp()
            }
            return element.exists && element.isHittable
        }

        /// Whichever container this screen actually scrolls, or the window.
        var firstScroller: XCUIElement {
            let candidates = [
                collectionViews.firstMatch,
                tables.firstMatch,
                scrollViews.firstMatch,
            ]
            for candidate in candidates where candidate.exists {
                return candidate
            }
            return self
        }

        /// Opens Settings and taps one of its rows by title.
        ///
        /// A **button**, not any element with the label: the Moderation section
        /// header reads "Moderation" too, and tapping a header does nothing —
        /// which looked exactly like a broken row.
        @discardableResult
        func openSettingsRow(_ title: String) -> Bool {
            guard openSettingsFromBrowseMenu() else { return false }
            guard navigationBars["Settings"].waitForExistence(timeout: 8) else { return false }
            return tapRow(title)
        }

        /// Taps the tappable thing carrying this label, scrolling to it first.
        @discardableResult
        func tapRow(_ title: String) -> Bool {
            let predicate = NSPredicate(
                format: "label CONTAINS %@ OR title CONTAINS %@", title, title)
            for query in [buttons, cells, staticTexts] {
                let row = query.matching(predicate).firstMatch
                guard scrollTo(row) else { continue }
                row.tapOrClick()
                return true
            }
            return false
        }
    }
#endif
