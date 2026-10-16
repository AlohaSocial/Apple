// SPDX-License-Identifier: MIT
import XCTest

#if os(iOS)
    import UIKit
    @MainActor
    final class NativeSidebarTests: XCTestCase {
        override func tearDown() async throws {
            XCUIDevice.shared.orientation = .portrait
            XCUIDevice.shared.appearance = .light
        }

        func testSidebarAndTopTabs() throws {
            try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad only")
            continueAfterFailure = false
            XCUIDevice.shared.orientation = .landscapeLeft
            let app = XCUIApplication()
            app.launchArguments = ["-AlohaMockServer", "-AlohaMockResetPhotoLayout"]
            app.launch()
            XCTAssertTrue(app.labelled("Test post number 1").waitForExistence(timeout: 20))
            shoot("98-native-ipad-initial")
            let sidebar = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'"))
                .firstMatch
            XCTAssertTrue(sidebar.waitForExistence(timeout: 5), "No system sidebar toggle")
            let homeRow = app.collectionViews.cells.containing(
                NSPredicate(format: "label == \"My Feed\"")
            ).firstMatch
            if !homeRow.exists || !homeRow.isHittable { sidebar.tap() }
            XCTAssertTrue(homeRow.waitForExistence(timeout: 5))
            shoot("98-native-ipad-expanded")
            sidebar.tap()
            shoot("98-native-ipad-toggled")
            XCTAssertTrue(app.buttons["My Feed"].firstMatch.isHittable)
            XCTAssertTrue(app.buttons["Photos"].firstMatch.isHittable)
            app.buttons["Photos"].firstMatch.tap()
            XCTAssertTrue(app.scrollViews["photos.feed"].waitForExistence(timeout: 8))
            shoot("98-native-ipad-top-photos")
            sidebar.tap()
            let discover = app.sidebarRow("Discover")
            XCTAssertTrue(discover.waitForExistence(timeout: 5))
            discover.tap()
            XCTAssertTrue(app.labelled("People to follow").waitForExistence(timeout: 8))
            XCTAssertTrue(app.segmentedControls.firstMatch.exists)
            shoot("98-native-ipad-discover")
            _ = app.sidebarRow("Discover")
            let menu = try XCTUnwrap(
                app.buttons.matching(NSPredicate(format: "label CONTAINS 'account menu'"))
                    .allElementsBoundByIndex.max(by: { $0.frame.maxY < $1.frame.maxY }))
            XCTAssertGreaterThan(menu.frame.minY, app.frame.height * 0.5)
            menu.tap()
            XCTAssertTrue(app.buttons["Switch account"].firstMatch.waitForExistence(timeout: 5))
            app.buttons["Switch account"].firstMatch.tap()
            shoot("98-native-ipad-account-picker")
            let bob = app.buttons.matching(
                NSPredicate(
                    format: "label == %@ OR label CONTAINS %@", "Bob", "@bob@cloud.example.test")
            ).firstMatch
            XCTAssertTrue(bob.waitForExistence(timeout: 5))
            bob.tap()
            XCUIDevice.shared.orientation = .portrait
            XCTAssertTrue(
                app.buttons.matching(NSPredicate(format: "label CONTAINS 'Bob, account menu'"))
                    .firstMatch.waitForExistence(timeout: 10))
        }
    }
#endif
