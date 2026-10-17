// SPDX-License-Identifier: MIT

import CoreGraphics
import Testing

@testable import AlohaUI

@Suite("A zoomed photograph moves as far as its own edges")
struct MediaZoomTests {
    private let phone = CGSize(width: 400, height: 800)

    @Test("A landscape picture fits the width and leaves bars above and below")
    func landscapeFitsWidth() {
        let fitted = MediaZoom.fittedSize(aspect: 2, in: phone)
        #expect(fitted == CGSize(width: 400, height: 200))
    }

    @Test("A tall picture fits the height")
    func portraitFitsHeight() {
        let fitted = MediaZoom.fittedSize(aspect: 0.25, in: phone)
        #expect(fitted == CGSize(width: 200, height: 800))
    }

    @Test("No aspect ratio means the whole container")
    func unknownAspect() {
        #expect(MediaZoom.fittedSize(aspect: nil, in: phone) == phone)
        #expect(MediaZoom.fittedSize(aspect: 0, in: phone) == phone)
    }

    @Test("At full view there is nowhere to move")
    func noRoomUnzoomed() {
        let offset = MediaZoom.clampedOffset(
            CGSize(width: 120, height: -90), zoom: 1, content: phone, container: phone)
        #expect(offset == .zero)
    }

    @Test("Zoomed, the picture stops at its edge on each side")
    func clampsToEdges() {
        // 400 × 200 at 3× is 1200 × 600 inside 400 × 800: 400 points of room
        // each way across, none up or down — the picture is still shorter
        // than the screen.
        let content = CGSize(width: 400, height: 200)
        let far = MediaZoom.clampedOffset(
            CGSize(width: 900, height: 500), zoom: 3, content: content, container: phone)
        #expect(far == CGSize(width: 400, height: 0))

        let back = MediaZoom.clampedOffset(
            CGSize(width: -900, height: -500), zoom: 3, content: content, container: phone)
        #expect(back == CGSize(width: -400, height: 0))
    }

    @Test("Within the room, a pan is taken as it is")
    func inside() {
        let offset = MediaZoom.clampedOffset(
            CGSize(width: 50, height: -30), zoom: 2, content: phone, container: phone)
        #expect(offset == CGSize(width: 50, height: -30))
    }
}
