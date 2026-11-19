// SPDX-License-Identifier: MIT

import CoreGraphics
import Testing

@testable import AlohaUI

@Suite("A media window opens in the media's shape")
struct MediaWindowSizingTests {
    @Test("Landscape keeps the long edge and follows the aspect")
    func landscape() {
        #expect(MediaWindowSizing.idealSize(aspect: 16.0 / 9.0) == CGSize(width: 1280, height: 720))
    }

    @Test("Portrait is held to a comfortable height")
    func portrait() {
        #expect(MediaWindowSizing.idealSize(aspect: 3.0 / 4.0) == CGSize(width: 750, height: 1000))
    }

    @Test("A panorama or a tall screenshot does not open as a ribbon")
    func extremes() {
        #expect(MediaWindowSizing.idealSize(aspect: 6).height == MediaWindowSizing.shortestEdge)
        #expect(MediaWindowSizing.idealSize(aspect: 0.2).width == MediaWindowSizing.shortestEdge)
    }

    @Test("Without dimensions it opens at the old landscape size")
    func unknown() {
        let fallback = CGSize(width: 1280, height: 800)
        #expect(MediaWindowSizing.idealSize(aspect: nil) == fallback)
        #expect(MediaWindowSizing.idealSize(aspect: 0) == fallback)
        #expect(MediaWindowSizing.idealSize(aspect: .infinity) == fallback)
    }
}
