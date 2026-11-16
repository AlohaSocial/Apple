// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import Testing

@testable import AlohaMedia

@Suite("The colours a photograph is made of")
struct PhotoColoursTests {

    /// `count` opaque pixels of one colour, as RGBA8.
    private func pixels(_ red: UInt8, _ green: UInt8, _ blue: UInt8, count: Int) -> [UInt8] {
        Array(repeating: [red, green, blue, 255], count: count).flatMap { $0 }
    }

    @Test("A picture of one colour is that colour")
    func singleColour() throws {
        let colours = try #require(PhotoColours.extract(rgba: pixels(200, 40, 40, count: 100)))
        #expect(colours.swatches.count == 1)
        let swatch = colours.swatches[0]
        #expect(abs(swatch.red - 200 / 255) < 0.01)
        #expect(abs(swatch.green - 40 / 255) < 0.01)
        #expect(swatch.weight == 1)
    }

    @Test("The colourful part of a mostly white picture still counts")
    func colourOutranksAWhiteWall() throws {
        let wall = pixels(245, 245, 245, count: 70)
        let jumper = pixels(30, 90, 200, count: 30)
        let colours = try #require(PhotoColours.extract(rgba: wall + jumper))
        #expect(colours.swatches.count == 2)
        // The blue leads even though it covers less: a tint is about the
        // picture's colour, not its background.
        #expect(colours.swatches[0].blue > colours.swatches[0].red)
    }

    @Test("Near shades of one colour are one swatch, not three")
    func neighboursMerge() throws {
        let shades =
            pixels(200, 40, 40, count: 30) + pixels(230, 40, 40, count: 30)
            + pixels(190, 70, 60, count: 30)
        let colours = try #require(PhotoColours.extract(rgba: shades))
        #expect(colours.swatches.count == 1)
    }

    @Test("Transparent pixels are not a colour")
    func transparencyIgnored() {
        let clear: [UInt8] = Array(repeating: [255, 0, 0, 0], count: 50).flatMap { $0 }
        #expect(PhotoColours.extract(rgba: clear) == nil)
    }

    @Test("A blurhash gives colours without any picture")
    func fromBlurHash() throws {
        let colours = try #require(PhotoColours.extract(blurhash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"))
        #expect(!colours.swatches.isEmpty)
        #expect(colours.swatches.count <= 3)
    }

    @Test("Nothing cached and no blurhash is no colours, and no request")
    func nothingWithoutCache() async {
        let url = URL(string: "https://example.invalid/never-fetched-\(UUID().uuidString).jpg")!
        #expect(await PhotoColours.cached(imageURLs: [url], blurhash: nil) == nil)
    }

    @Test("A drawn picture is counted from its thumbnail")
    func fromCGImage() throws {
        let side = 10
        var bytes = pixels(20, 160, 60, count: side * side)
        let image = try bytes.withUnsafeMutableBytes { buffer -> CGImage in
            let context = try #require(
                CGContext(
                    data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                    bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try #require(context.makeImage())
        }
        let colours = try #require(PhotoColours.extract(from: image))
        #expect(colours.swatches[0].green > colours.swatches[0].red)
    }
}
