// SPDX-License-Identifier: MIT

import XCTest

#if os(iOS)
    /// Beyond "does the screen appear": does acting on it do what it says.
    /// `@MainActor` because every `XCUIElement` member is: without it each
    /// `tap()` and `waitForExistence` is a nonisolated call into main-actor
    /// state, which is a warning per line and a build failure once warnings
    /// are errors (docs/12 §6).
    @MainActor
    final class InteractionTourTests: XCTestCase {
        private var app: XCUIApplication!

        private func launch(_ extra: [String] = []) {
            app = XCUIApplication()
            app.launchArguments = ["-AlohaMockServer"] + extra
            app.launch()
            app.dismissSystemAlertsIfPresent()
            XCTAssertTrue(
                app.labelled("Test post number 1").waitForExistence(timeout: 15),
                "Home did not render")
        }

        // The `async` overrides, not `setUpWithError`/`tearDown`: XCTest
        // declares those nonisolated, so an override of one stays nonisolated
        // even in a `@MainActor` class, and every line here touches
        // `XCUIApplication`, which is main-actor. The async forms adopt the
        // class's isolation instead.
        override func setUp() async throws {
            continueAfterFailure = true
        }

        func testFavouriteAndBoostChangeState() {
            launch()
            // Bob's content-warned post is first and starts at zero of each.
            let favourite = app.buttons.matching(identifier: "Favourite").element(boundBy: 0)
            XCTAssertTrue(favourite.waitForExistence(timeout: 5))
            favourite.tap()
            sleep(1)
            shoot("30-favourited")
            let boost = app.buttons.matching(identifier: "Boost").element(boundBy: 0)
            boost.tap()
            sleep(1)
            shoot("31-boosted")
            XCTAssertTrue(
                app.staticTexts["1"].firstMatch.waitForExistence(timeout: 3),
                "Neither count moved to 1 after favourite and boost")
        }

        func testComposeAndPost() {
            launch()
            app.buttons["New post"].firstMatch.tap()
            let editor = app.textViews.firstMatch
            XCTAssertTrue(editor.waitForExistence(timeout: 5), "No editor")
            editor.tap()
            editor.typeText("Hello from the screen tour #nextcloud")
            sleep(1)
            shoot("32-composer-typed")
            let post = app.buttons["Post"].firstMatch
            XCTAssertTrue(post.isEnabled, "Post button stayed disabled with text")
            post.tap()
            XCTAssertTrue(
                app.labelled("Hello from the screen tour").waitForExistence(timeout: 10),
                "Posted status did not appear at the top of Home")
            XCTAssertFalse(
                app.labelled("in 0s").exists, "A just-posted status claimed to be from the future")
            shoot("33-after-post")
        }

        func testReplyPrefillsContext() {
            launch()
            // Bob's post: the reply must name him and say what it answers.
            let reply = app.buttons.matching(identifier: "Reply").element(boundBy: 0)
            XCTAssertTrue(reply.waitForExistence(timeout: 5))
            reply.tap()
            let editor = app.textViews.firstMatch
            XCTAssertTrue(editor.waitForExistence(timeout: 5), "Reply composer missing")
            XCTAssertTrue(
                app.labelled("Replying to @bob").waitForExistence(timeout: 3),
                "Reply context line missing")
            XCTAssertTrue(
                (editor.value as? String)?.hasPrefix("@bob") == true,
                "Reply text not prefilled with @bob, got \(String(describing: editor.value))")
            sleep(1)
            shoot("34-reply-composer")
            app.buttons["Cancel"].firstMatch.tap()
        }

        func testPhotosStartsWithPostFeedAndCanShowGrid() {
            launch(["-AlohaMockResetPhotoLayout"])
            app.tabBars.buttons["Photos"].tap()
            let feed = app.scrollViews["photos.feed"].firstMatch
            XCTAssertTrue(
                feed.waitForExistence(timeout: 10), "Photos did not default to the post feed")
            XCTAssertTrue(app.buttons["Favourite"].firstMatch.exists, "Photo post actions missing")
            XCTAssertTrue(
                app.buttons["More actions"].firstMatch.exists, "Photo post header missing")
            shoot("56-photos-feed")
            app.buttons["Photo layout"].firstMatch.tap()
            app.buttons["Grid"].firstMatch.tap()
            XCTAssertFalse(feed.exists, "Grid switch did not change the layout")
            shoot("57-photos-grid")
            app.buttons["Photo layout"].firstMatch.tap()
            app.buttons["Feed"].firstMatch.tap()
            XCTAssertTrue(feed.waitForExistence(timeout: 5))
        }

        func testMediaViewerOpensFromPhotos() {
            launch()
            app.tabBars.buttons["Photos"].tap()
            app.buttons["Photo layout"].firstMatch.tap()
            app.buttons["Grid"].firstMatch.tap()
            let tile = app.buttons.matching(
                NSPredicate(format: "label CONTAINS 'photograph'")
            ).firstMatch
            XCTAssertTrue(tile.waitForExistence(timeout: 10), "No photo tile")
            tile.tap()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5), "Viewer did not open")
            sleep(1)
            shoot("35-media-viewer")
            app.buttons["Close"].tap()
        }

        /// The switcher has to actually switch. The previous version of this
        /// test tapped and took a photograph, which a picker that changed
        /// nothing passed just as happily.
        func testSourceToggleActuallySwitchesTimeline() {
            launch()
            let global = app.buttons["Global"].firstMatch
            XCTAssertTrue(global.waitForExistence(timeout: 5), "No source toggle")
            XCTAssertTrue(app.buttons["My feed"].exists, "Toggle is missing My feed")
            XCTAssertTrue(app.buttons["Local"].exists, "Toggle is missing Local")

            global.tap()
            XCTAssertTrue(
                app.labelled("Global timeline post").waitForExistence(timeout: 10),
                "Tapping Global did not load the global timeline")
            shoot("36-global")

            app.buttons["Local"].firstMatch.tap()
            XCTAssertTrue(
                app.labelled("Local timeline post").waitForExistence(timeout: 10),
                "Tapping Local did not load the local timeline")
            shoot("37-local")

            app.buttons["My feed"].firstMatch.tap()
            sleep(2)
            shoot("38-back-to-my-feed")
            XCTAssertTrue(
                app.labelled("Test post number").waitForExistence(timeout: 10),
                "Tapping My feed did not come back to the home timeline")
        }

        func testAccountMenuReachesDiscoverAndLists() {
            launch()
            XCTAssertTrue(
                app.openFromAccountMenu("Discover"), "Discover missing from the account menu")
            // A section that only exists once the server has answered. This
            // used to wait for "nextcloud", which is a trending *hashtag* on
            // the Tags tab — Discover opens on People, so the wait could only
            // ever time out.
            XCTAssertTrue(
                app.labelled("People to follow").waitForExistence(timeout: 10),
                "Discover did not load")
            sleep(1)
            shoot("37-explore")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(
                app.openFromAccountMenu("Your lists"), "Your lists missing from the account menu")
            XCTAssertTrue(app.labelled("Colleagues").waitForExistence(timeout: 10), "Lists empty")
            shoot("38-lists")
        }

        func testSwitchingAccounts() {
            launch()
            // The switcher lives top-left on the phone.
            let switcher = app.buttons.matching(
                NSPredicate(format: "label CONTAINS 'account menu'")
            ).firstMatch
            XCTAssertTrue(switcher.waitForExistence(timeout: 5), "No account switcher")
            switcher.tap()
            app.buttons["Switch account"].firstMatch.tap()
            shoot("99-phone-account-options")
            print("PHONE ACCOUNT OPTIONS:\n\(app.debugDescription)")
            let other = app.buttons.matching(
                NSPredicate(format: "label == %@ OR label CONTAINS %@", "Bob", "@bob@")
            ).firstMatch
            XCTAssertTrue(other.waitForExistence(timeout: 5), "Second account not offered")
            other.tap()
            sleep(3)
            XCTAssertTrue(
                app.labelled("Test post number 1").waitForExistence(timeout: 10),
                "Timeline did not come back after switching account")
            XCTAssertTrue(
                app.buttons.matching(
                    NSPredicate(format: "label CONTAINS %@", "Bob, account menu")
                ).firstMatch.waitForExistence(timeout: 5))
            shoot("51-switched-account")
        }

        func testErrorStateIsVisible() {
            app = XCUIApplication()
            app.launchArguments = ["-AlohaMockServer", "-AlohaMockFailing"]
            app.launch()
            app.dismissSystemAlertsIfPresent()
            // A server that refuses everything: the strip has to say so rather
            // than leaving an empty screen.
            let strip = app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "label CONTAINS[c] 'asking for a moment'"
                        + " OR label CONTAINS[c] 'retry' OR label CONTAINS[c] 'offline'")
            ).firstMatch
            XCTAssertTrue(strip.waitForExistence(timeout: 20), "No error was shown at all")
            shoot("52-error-state")
        }

        func testConversationsShowChatRows() {
            launch()
            let tab = app.tabBars.buttons["Messages"]
            XCTAssertTrue(tab.waitForExistence(timeout: 8), "Messages tab missing")
            tab.tap()
            XCTAssertTrue(
                app.labelled("Bob").firstMatch.waitForExistence(timeout: 10),
                "No conversation row rendered")
            XCTAssertFalse(
                app.labelled("Test post number 1 with").exists,
                "Conversations is showing the home timeline")
            shoot("46-conversations")
        }

        func testPollAndCardAndBoostRender() {
            launch()
            // The poll post mentions Bob; its thread shows poll, mention and card.
            let pollRow = app.labelled("which one do you use")
            for _ in 0..<6 where !pollRow.exists { app.swipeUp() }
            XCTAssertTrue(pollRow.exists, "Poll row never appeared")
            shoot("39-poll-card")
            pollRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            XCTAssertTrue(
                app.labelled("Nextcloud Social").waitForExistence(timeout: 8),
                "Poll options did not render")
            XCTAssertTrue(app.labelled("12 votes").exists, "Poll tally missing")
            shoot("39b-poll-thread")
            app.navigationBars.buttons.firstMatch.tap()

            let boosted = app.labelled("The post Bob boosted")
            for _ in 0..<4 where !boosted.exists { app.swipeUp() }
            XCTAssertTrue(boosted.exists, "Boost row never appeared")
            XCTAssertTrue(app.labelled("Boosted by Bob").exists, "Boost context line missing")
            shoot("40-boost-reply")
        }

        func testLargeText() {
            launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"])
            sleep(1)
            shoot("41-large-text-home")
            app.tabBars.buttons["Messages"].tap()
            sleep(1)
            shoot("42-large-text-messages")
        }

        /// This test used to be called `testDarkModeAndLargeText` and only ever
        /// changed the text size. Nothing had looked at the app in the dark.
        func testDarkMode() {
            XCUIDevice.shared.appearance = .dark
            defer { XCUIDevice.shared.appearance = .light }
            launch()
            sleep(1)
            shoot("47-dark-home")
            app.tabBars.buttons["Photos"].tap()
            sleep(2)
            shoot("48-dark-photos")
            app.tabBars.buttons["Messages"].tap()
            sleep(1)
            shoot("49-dark-messages")
            if app.openSettingsFromBrowseMenu() {
                sleep(1)
                shoot("50-dark-settings")
            }
        }

        /// A conversation opens as a chat, and a message typed at its foot
        /// lands in it as your own bubble.
        func testConversationThreadSendsMessage() {
            launch()
            app.tabBars.buttons["Messages"].tap()
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Unread. Bob'"))
                .firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), "No conversation row")
            row.tap()
            XCTAssertTrue(
                app.labelled("Private conversation").waitForExistence(timeout: 10),
                "Thread header missing")
            XCTAssertTrue(
                app.labelled("Test post number 2 with").waitForExistence(timeout: 10),
                "Last message not shown as a bubble")
            shoot("53-conversation-thread")

            let field = app.descendants(matching: .any)
                .matching(identifier: "conversation.field").firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5), "Message field missing")
            field.tap()
            field.typeText("Hello from the thread")
            app.buttons["Send"].firstMatch.tap()
            XCTAssertTrue(
                app.labelled("Hello from the thread").waitForExistence(timeout: 10),
                "Sent message did not appear")
            shoot("54-conversation-sent")
        }

        /// A video card opens the watch page rather than the thread: player,
        /// title, follow button, action pills and comments.
        func testVideoWatchPageOpens() {
            launch()
            app.tabBars.buttons["Videos"].tap()
            let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play '"))
                .firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 10), "No video card")
            card.tap()
            XCTAssertTrue(
                app.staticTexts["Comments"].waitForExistence(timeout: 10), "Watch page missing")
            // The mock's video is the signed-in account's own, so there is no
            // Follow button to look for; the action pills are the check.
            XCTAssertTrue(app.buttons["Reply"].firstMatch.exists, "Action pills missing")
            XCTAssertTrue(
                app.labelled("Reply 1 to that").waitForExistence(timeout: 10),
                "Comments did not load")
            shoot("55-video-watch")
        }

        func testInitialFeedChoiceChangesTabs() {
            app = XCUIApplication()
            app.launchArguments = ["-AlohaMockServer", "-AlohaMockModeSelection"]
            app.launch()
            let title = app.labelled("Which feeds do you want?")
            XCTAssertTrue(title.waitForExistence(timeout: 15))
            for name in ["Photos", "Video", "Shorts"] {
                let choice = app.buttons.matching(
                    NSPredicate(format: "label BEGINSWITH %@", name + ",")
                ).firstMatch
                XCTAssertTrue(choice.waitForExistence(timeout: 5), "Feed choice missing: \(name)")
                choice.tap()
                XCTAssertTrue(title.exists, "Changing a feed dismissed its sheet")
            }
            app.buttons["Continue"].firstMatch.tap()
            XCTAssertTrue(app.tabBars.buttons["My Feed"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.tabBars.buttons["Photos"].exists)
            XCTAssertFalse(app.tabBars.buttons["Shorts"].exists)

        }

        func testWelcomeAtAccessibilityTextSize() {
            app = XCUIApplication()
            app.launchArguments = [
                "-AlohaMockServer", "-AlohaMockNoAccount",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
            app.launch()
            let skip = app.buttons["Skip"].firstMatch
            XCTAssertTrue(skip.waitForExistence(timeout: 10))
            skip.tap()
            let field = app.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            if !field.isHittable { app.scrollViews["welcome-sign-in-content"].swipeUp() }
            XCTAssertTrue(field.isHittable, "Server field unreachable with large text")
            field.tap()
            field.typeText("cloud.example.test")
            let next = app.buttons["Continue"].firstMatch
            for _ in 0..<3 where !next.isHittable {
                app.scrollViews["welcome-sign-in-content"].swipeUp()
            }
            XCTAssertTrue(next.isHittable, "Continue unreachable above keyboard")
            shoot("46-welcome-large-text")
            next.tap()
            XCTAssertTrue(app.labelled("Before you start").waitForExistence(timeout: 5))
        }

        func testWelcomeAndSignIn() {
            app = XCUIApplication()
            app.launchArguments = ["-AlohaMockServer", "-AlohaMockNoAccount"]
            app.launch()
            XCTAssertTrue(
                app.labelled("A calmer client").waitForExistence(timeout: 10),
                "Introduction missing")
            shoot("44-welcome")
            app.buttons["Skip"].firstMatch.tap()
            let field = app.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5), "Server address missing")
            XCTAssertFalse(app.buttons["Continue"].firstMatch.isEnabled)
            app.buttons["Back"].firstMatch.tap()
            XCTAssertTrue(app.labelled("Quiet by default").waitForExistence(timeout: 5))
            app.buttons["Continue"].firstMatch.tap()
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText("cloud.example.test")
            app.buttons["Continue"].firstMatch.tap()
            XCTAssertTrue(
                app.labelled("Before you start").waitForExistence(timeout: 5),
                "Terms gate missing after introduction")
            shoot("43-terms")
            app.buttons["Agree and continue"].firstMatch.tap()
            XCTAssertTrue(
                app.textFields.firstMatch.waitForExistence(timeout: 5),
                "Sign-in did not open")
            shoot("45-sign-in")
        }
    }
#endif
