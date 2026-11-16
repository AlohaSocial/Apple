// SPDX-License-Identifier: MIT

import Testing

@testable import AlohaDesign

@Suite("A photograph tints the page around it, and never past reading")
struct PhotoTintTests {

    private let warmLight = ServerAccent.RGB(red: 0.984, green: 0.957, blue: 0.918)
    private let black = ServerAccent.RGB.black
    private let white = ServerAccent.RGB.white
    private let swatches: [ServerAccent.RGB] = [
        ServerAccent.RGB(red: 1, green: 0, blue: 0.6),  // neon pink
        ServerAccent.RGB(red: 0.1, green: 0.9, blue: 0.2),  // acid green
        ServerAccent.RGB(red: 0.05, green: 0.1, blue: 0.9),  // deep blue
        ServerAccent.RGB(red: 1, green: 1, blue: 0),  // yellow
        ServerAccent.RGB(red: 0.5, green: 0.5, blue: 0.5),  // grey
    ]

    /// Body text keeps AAA, and the faintest label keeps 4.5:1 — or what the
    /// plain ground gave it, if that was already less.
    private func assertReadable(_ washed: ServerAccent.RGB, ground: ServerAccent.RGB, isDark: Bool)
    {
        let text: ServerAccent.RGB = isDark ? .white : .black
        let faint = PhotoTint.faintestText(isDark: isDark)
        #expect(ServerAccent.contrast(washed, text) >= PhotoTint.bodyContrast)
        let floor = min(ServerAccent.minimumContrast, ServerAccent.contrast(ground, faint))
        #expect(ServerAccent.contrast(washed, faint) >= floor - 0.0001)
    }

    @Test("Text on a tinted light page stays readable")
    func lightPageStaysReadable() throws {
        for swatch in swatches {
            let tint = try #require(
                PhotoTint.page(from: [swatch], ground: warmLight, isDark: false))
            assertReadable(tint.colours[0], ground: warmLight, isDark: false)
        }
    }

    @Test("Text on a tinted dark page stays readable")
    func darkPageStaysReadable() throws {
        let dim = ServerAccent.RGB(red: 0.11, green: 0.11, blue: 0.13)
        for ground in [black, dim] {
            for swatch in swatches {
                let tint = try #require(
                    PhotoTint.page(from: [swatch], ground: ground, isDark: true))
                assertReadable(tint.colours[0], ground: ground, isDark: true)
            }
        }
    }

    @Test("The wash is visible: a colourful photograph moves the page")
    func washIsNotNothing() throws {
        let tint = try #require(
            PhotoTint.page(from: [swatches[2]], ground: warmLight, isDark: false))
        #expect(tint.colours[0] != warmLight)
        // Towards blue, as the photograph is.
        #expect(tint.colours[0].blue - tint.colours[0].red > warmLight.blue - warmLight.red)
    }

    @Test("A grey photograph makes a grey wash, never an invented hue")
    func greyStaysGrey() throws {
        let tint = try #require(
            PhotoTint.page(from: [swatches[4]], ground: white, isDark: false))
        let colour = tint.colours[0]
        #expect(abs(colour.red - colour.green) < 0.001)
        #expect(abs(colour.green - colour.blue) < 0.001)
    }

    @Test("No colours, no tint")
    func nothingToTintWith() {
        #expect(PhotoTint.page(from: [], ground: white, isDark: false) == nil)
        #expect(PhotoTint.backdrop(from: []) == nil)
    }

    @Test("At most three colours are used")
    func threeAtMost() throws {
        let tint = try #require(PhotoTint.page(from: swatches, ground: white, isDark: false))
        #expect(tint.colours.count == 3)
    }

    @Test("The viewer's backdrop is deep enough for its white controls")
    func backdropIsDeep() throws {
        let tint = try #require(PhotoTint.backdrop(from: swatches))
        for colour in tint.colours + [tint.base] {
            #expect(ServerAccent.contrast(colour, white) >= 10)
        }
    }

    @Test("HSL round-trips a colour")
    func hslRoundTrip() {
        for swatch in swatches {
            let back = PhotoTint.HSL(swatch).rgb
            #expect(abs(back.red - swatch.red) < 0.0001)
            #expect(abs(back.green - swatch.green) < 0.0001)
            #expect(abs(back.blue - swatch.blue) < 0.0001)
        }
    }
}
