// SPDX-License-Identifier: MIT

import XCTest

/// Plays the mock instance's video, for real.
///
/// Every other tour checked that the watch page *opened* — and every bug that
/// made a video refuse to play was invisible to that check, because the poster,
/// the title and the pills all load through the in-process mock while the
/// player opens its own connection. These tests run the app against a loopback
/// socket (`-AlohaMockMedia`) that serves the file and the ladder only to a
/// request carrying the account's bearer token, and then ask the screen whether
/// the picture moved.
@MainActor
final class VideoPlaybackTests: XCTestCase {
    private var app: XCUIApplication!

    /// The player's rectangle, as a fraction of the screen: wide and tall
    /// enough to hold the moving bar whatever the device does with the rest of
    /// the page.
    private let playerRegion = CGRect(x: 0.05, y: 0.12, width: 0.9, height: 0.4)

    override func setUp() async throws {
        continueAfterFailure = true
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-AlohaMockServer", "-AlohaMockMedia"] + extra
        app.launch()
        app.dismissSystemAlertsIfPresent()
        XCTAssertTrue(
            app.labelled("Test post number 1").waitForExistence(timeout: 20),
            "Home did not render")
    }

    /// The Videos tab, then the first card, which is the mock's video status.
    private func openVideoPost() {
        app.tabBars.buttons["Videos"].tap()
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play '"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "No video card in Videos")
        card.tap()
        XCTAssertTrue(
            app.staticTexts["Comments"].waitForExistence(timeout: 15), "Watch page missing")
    }

    private var failureCard: XCUIElement {
        app.labelled("could not be played")
    }

    /// Three luminance readings half a second apart. A playing video moves its
    /// picture between them; a paused one, a poster and a black rectangle do
    /// not.
    private func pictureMotion(samples: Int = 4, interval: TimeInterval = 0.45) -> Double {
        var readings: [Double] = []
        for _ in 0..<samples {
            if let value = meanLuminance(of: playerRegion, in: XCUIScreen.main.screenshot()) {
                readings.append(value)
            }
            Thread.sleep(forTimeInterval: interval)
        }
        guard let low = readings.min(), let high = readings.max() else { return 0 }
        return high - low
    }

    /// The picture moves, so the file decoded and the display is ticking.
    private func assertPlaying(_ message: String) {
        // Readiness and the first frames take a moment even on loopback.
        var motion: Double = 0
        for _ in 0..<6 {
            motion = pictureMotion()
            if motion > 0.01 { break }
        }
        XCTAssertFalse(failureCard.exists, "\(message): the failure card is up — \(failureCard.label)")
        XCTAssertGreaterThan(motion, 0.01, "\(message): the picture never moved")
    }

    // MARK: - The two rungs

    /// The file first, because that is the order a token-protected account
    /// gets: AVFoundation's own HLS loader drops the header.
    func testFilePlaysWithTheAccountsToken() {
        launch()
        openVideoPost()
        assertPlaying("direct file")
        shoot("60-video-file-plays")

        // The system player's own controls, which is what "bedienbar" means:
        // tapping the picture reveals them and pause has to stop the clock.
        app.otherElements.firstMatch.tap()
        let pause = app.buttons["Pause"]
        if pause.waitForExistence(timeout: 5) {
            pause.tap()
            let paused = pictureMotion()
            XCTAssertLessThan(paused, 0.01, "Paused, but the picture kept moving")
            shoot("61-video-file-paused")
            let play = app.buttons["Play"]
            if play.waitForExistence(timeout: 5) {
                play.tap()
                assertPlaying("resumed")
            }
        } else {
            XCTFail("No pause control appeared on the player")
        }
    }

    /// The ladder, when the file refuses: the fallback chain has to be real
    /// rather than a comment.
    func testLadderPlaysWhenTheFileIsRefused() {
        launch(["-AlohaMockMediaRefuseFile"])
        openVideoPost()
        assertPlaying("ladder after a 401 from the file")
        shoot("62-video-ladder-plays")
    }

    /// A rung that accepts the connection and says nothing is the other half
    /// of the same story: the stall deadline has to move on.
    func testLadderPlaysWhenTheFileNeverAnswers() {
        launch(["-AlohaMockMediaStallFile"])
        openVideoPost()
        assertPlaying("ladder after the file stalled")
        shoot("63-video-ladder-after-stall")
    }

    /// Nothing plays, so the card appears — and only then.
    func testFailureCardOnlyWhenNoRungPlays() {
        launch(["-AlohaMockMediaRefuseFile", "-AlohaMockMediaRefuseLadder"])
        openVideoPost()
        XCTAssertTrue(
            failureCard.waitForExistence(timeout: 30),
            "Neither rung plays, yet no failure card appeared")
        shoot("64-video-failure-card")
    }
}
