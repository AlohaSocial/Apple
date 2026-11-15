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

    /// Every label on the page, for a failure that has to say what the player
    /// itself said — the card's second line names the host and the reason.
    private var visibleText: String {
        app.staticTexts.allElementsBoundByIndex.map(\.label)
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
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
        XCTAssertFalse(
            failureCard.exists, "\(message): the failure card is up — \(visibleText)")
        XCTAssertGreaterThan(motion, 0.01, "\(message): the picture never moved")
    }

    // MARK: - The player's own controls
    //
    // AVKit fades its controls about three seconds after they appear while
    // the item plays. On a hosted runner a single accessibility query can take
    // a second or more, so "find the Pause button, then tap it" lost the race:
    // the button was found, faded, and the tap's own lookup came back empty
    // (run 43608049514). Nothing here looks a control up twice. It is read
    // with `snapshot()`, which reports a faded control as absent rather than
    // failing the test, and pressed by its place on the screen, which needs no
    // second lookup. Whether a press took is read from the control afterwards.

    /// The Play/Pause control as it is now, or nil while the controls are
    /// faded.
    private var playPauseNow: XCUIElementSnapshot? {
        try? app.buttons["Play/Pause"].snapshot()
    }

    /// Waits for the Play/Pause control, bringing faded controls back with a
    /// tap on the picture — and only faded ones, because the same tap hides
    /// controls that show. With `label`, waits for it to offer that.
    private func waitForPlayPause(
        _ label: String? = nil, on surface: XCUIElement, timeout: TimeInterval
    ) -> XCUIElementSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let control = playPauseNow {
                if label == nil || control.label == label { return control }
            } else {
                surface.tap()
            }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return nil
    }

    /// Presses Play/Pause until it offers `label`. Every press follows a
    /// reading of the control in the other state, so a press that took is
    /// never undone by a second one; a press that landed while the controls
    /// had faded only brought them back, and the next reading says so.
    private func pressPlayPause(
        at button: XCUICoordinate, until label: String, on surface: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            guard let control = waitForPlayPause(on: surface, timeout: 3) else { continue }
            if control.label == label { return true }
            button.tap()
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return false
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
        // tapping the picture reveals them, and pause and play have to change
        // the player's state. The controls are read rather than the pixels
        // here: the mock's video is ten seconds long, and by the time a runner
        // has opened the page and taken the readings above, a resumed picture
        // can already be its last frame — which is a fact about the fixture,
        // not about the player.
        let surface = app.otherElements["Video"].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 10), "No video surface to tap")
        guard let control = waitForPlayPause(on: surface, timeout: 10) else {
            XCTFail("No player controls appeared on the player")
            return
        }
        // The control sits in the middle of the picture and does not move, so
        // its place, read once, is where every later press goes.
        let button = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: control.frame.midX, dy: control.frame.midY))
        // Ten seconds of fixture can end while a slow runner takes the
        // readings above; the control then offers Play, and pressing it on a
        // finished item does nothing. Rewind to the first frame so there is
        // somewhere to play from, then start it again. A finished item is
        // paused, and paused controls do not fade.
        if control.label == "Play" {
            let rewind = app.buttons["Skip Backward"]
            if rewind.exists { rewind.tap() }
            if waitForPlayPause("Pause", on: surface, timeout: 1) == nil {
                _ = pressPlayPause(at: button, until: "Pause", on: surface, timeout: 10)
            }
        }
        XCTAssertNotNil(
            waitForPlayPause("Pause", on: surface, timeout: 10),
            "No pause control appeared on the player")
        XCTAssertTrue(
            pressPlayPause(at: button, until: "Play", on: surface, timeout: 15),
            "Pausing did not turn the control into Play")
        shoot("61-video-file-paused")
        XCTAssertTrue(
            pressPlayPause(at: button, until: "Pause", on: surface, timeout: 15),
            "Resuming did not turn the control into Pause")
        XCTAssertFalse(failureCard.exists, "Resuming put the failure card up")
        shoot("62-video-file-resumed")
    }

    /// The ladder, when the file refuses: the fallback chain has to be real
    /// rather than a comment.
    func testLadderPlaysWhenTheFileIsRefused() {
        launch(["-AlohaMockMediaRefuseFile"])
        openVideoPost()
        assertPlaying("ladder after a 401 from the file")
        shoot("63-video-ladder-plays")
    }

    /// A rung that accepts the connection and says nothing is the other half
    /// of the same story: the stall deadline has to move on.
    func testLadderPlaysWhenTheFileNeverAnswers() {
        launch(["-AlohaMockMediaStallFile"])
        openVideoPost()
        assertPlaying("ladder after the file stalled")
        shoot("64-video-ladder-after-stall")
    }

    /// Nothing plays, so the card appears — and only then.
    func testFailureCardOnlyWhenNoRungPlays() {
        launch(["-AlohaMockMediaRefuseFile", "-AlohaMockMediaRefuseLadder"])
        openVideoPost()
        XCTAssertTrue(
            failureCard.waitForExistence(timeout: 30),
            "Neither rung plays, yet no failure card appeared")
        shoot("65-video-failure-card")
    }
}
