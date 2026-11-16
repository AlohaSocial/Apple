// SPDX-License-Identifier: MIT

import Testing

@testable import AlohaUI

@Suite("Turning an action on is celebrated, within reason")
struct CelebrationTests {

    @Test("A favourite and a bookmark burst; a boost turns instead; a reply does nothing")
    func whichActionsBurst() {
        #expect(StatusActionButton.celebrates(.heart, reduceMotion: false))
        #expect(StatusActionButton.celebrates(.pop, reduceMotion: false))
        #expect(!StatusActionButton.celebrates(.spin, reduceMotion: false))
        #expect(!StatusActionButton.celebrates(.plain, reduceMotion: false))
    }

    @Test("Reduce Motion: no burst at all, only the state change")
    func reduceMotion() {
        for style in [StatusActionButton.Style.heart, .pop, .spin, .plain] {
            #expect(!StatusActionButton.celebrates(style, reduceMotion: true))
        }
    }

    @Test("Hearts fan upwards; sparks go all the way round")
    func particleDirections() {
        let hearts = CelebrationBurst.particles(for: .hearts)
        #expect(hearts.count == 6)
        // Nothing thrown below the horizontal: a heart going down reads as
        // one falling.
        #expect(hearts.allSatisfy { abs($0) < 90 })
        #expect(CelebrationBurst.particles(for: .sparks).count == 8)
    }

    @Test("The burst is short enough to be over before the next tap")
    func duration() {
        #expect(CelebrationBurst.duration <= 0.6)
    }
}
