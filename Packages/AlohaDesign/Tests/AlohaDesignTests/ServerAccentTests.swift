// SPDX-License-Identifier: MIT

import Testing

@testable import AlohaDesign

@Suite("The colour the server wears")
struct ServerAccentTests {

    private let light = ServerAccent.RGB(red: 0.99, green: 0.98, blue: 0.97)
    private let dark = ServerAccent.RGB(red: 0.09, green: 0.08, blue: 0.08)

    @Test("Hex comes in long, short and bare")
    func parsing() {
        #expect(ServerAccent.components(hex: "#0082c9") != nil)
        #expect(ServerAccent.components(hex: "0082c9") != nil)
        #expect(ServerAccent.components(hex: "#FFF")?.red == 1)
        #expect(ServerAccent.components(hex: "  #0082C9 ") != nil)
        // Anything that is not a colour is no colour, never a guess.
        #expect(ServerAccent.components(hex: nil) == nil)
        #expect(ServerAccent.components(hex: "") == nil)
        #expect(ServerAccent.components(hex: "blue") == nil)
        #expect(ServerAccent.components(hex: "#12345") == nil)
        #expect(ServerAccent.components(hex: "#zzzzzz") == nil)
    }

    @Test("A colour that already reads is left exactly where it is")
    func alreadyLegible() throws {
        let deep = try #require(ServerAccent.components(hex: "#005a8c"))
        #expect(ServerAccent.contrast(deep, light) >= ServerAccent.minimumContrast)
        let resolved = try #require(ServerAccent.legibleComponents(deep, on: light))
        #expect(resolved == deep)
    }

    @Test("Nextcloud's own blue is 4.0:1 on the light ground, so it is darkened")
    func nextcloudBlueNeedsHelp() throws {
        // Close enough to look fine and far enough to fail, which is exactly
        // the case the guard exists for.
        let blue = try #require(ServerAccent.components(hex: "#0082c9"))
        let ratio = ServerAccent.contrast(blue, light)
        #expect(ratio > 3.9 && ratio < 4.1)

        let fixed = try #require(ServerAccent.legibleComponents(blue, on: light))
        #expect(fixed != blue)
        #expect(ServerAccent.contrast(fixed, light) >= ServerAccent.minimumContrast)
        // Still blue: only the lightness gave.
        #expect(fixed.blue > fixed.green)
        #expect(fixed.green > fixed.red)
    }

    @Test("A colour too pale for a light ground is darkened until it reads")
    func darkensOnLight() throws {
        // A cheerful yellow: 1.07:1 against near-white, and unusable raw.
        let yellow = try #require(ServerAccent.components(hex: "#ffe36e"))
        #expect(ServerAccent.contrast(yellow, light) < ServerAccent.minimumContrast)

        let fixed = try #require(ServerAccent.legibleComponents(yellow, on: light))
        #expect(ServerAccent.contrast(fixed, light) >= ServerAccent.minimumContrast)
        // Darkened, not replaced: it is still recognisably their colour.
        #expect(fixed.red > fixed.blue)
        #expect(fixed.green > fixed.blue)
    }

    @Test("A colour too deep for a dark ground is lightened until it reads")
    func lightensOnDark() throws {
        let navy = try #require(ServerAccent.components(hex: "#10204a"))
        #expect(ServerAccent.contrast(navy, dark) < ServerAccent.minimumContrast)

        let fixed = try #require(ServerAccent.legibleComponents(navy, on: dark))
        #expect(ServerAccent.contrast(fixed, dark) >= ServerAccent.minimumContrast)
        #expect(fixed.blue > navy.blue)
    }

    @Test("Every named colour a Nextcloud ships with survives both grounds")
    func nextcloudDefaults() throws {
        for hex in ["#0082c9", "#745bca", "#c98879", "#c9c9c9", "#000000", "#ffffff"] {
            for ground in [light, dark] {
                let start = try #require(ServerAccent.components(hex: hex))
                let fixed = try #require(
                    ServerAccent.legibleComponents(start, on: ground),
                    "\(hex) could not be made legible")
                #expect(
                    ServerAccent.contrast(fixed, ground) >= ServerAccent.minimumContrast,
                    "\(hex) still fails on \(ground)")
            }
        }
    }

    @Test("A colour that cannot be rescued is declined rather than forced")
    func givesUpHonestly() {
        // A mid-grey on a mid-grey ground: nothing along the lightness axis
        // reaches 4.5:1 without crossing the background.
        let ground = ServerAccent.RGB(red: 0.5, green: 0.5, blue: 0.5)
        let grey = ServerAccent.components(hex: "#808080")
        #expect(ServerAccent.legibleComponents(grey!, on: ground) == nil)
        #expect(ServerAccent.legible(hex: "#808080", on: ground) == nil)
    }

    @Test("Text on the accent is whichever of black and white reads")
    func textColour() throws {
        let navy = try #require(ServerAccent.components(hex: "#10204a"))
        #expect(ServerAccent.contrast(.white, navy) > ServerAccent.contrast(.black, navy))
        #expect(ServerAccent.textColour(on: navy, preferring: nil) == .white)

        let yellow = try #require(ServerAccent.components(hex: "#ffe36e"))
        #expect(ServerAccent.contrast(.black, yellow) > ServerAccent.contrast(.white, yellow))
        #expect(ServerAccent.textColour(on: yellow, preferring: nil) == .black)
    }

    @Test("The accent and its text always meet AA, whatever the server sent")
    func accentCarriesItsTextEverywhere() throws {
        // The invariant `PaletteTests` asserts for the built-in themes, held
        // for a colour nobody here chose.
        for hex in ["#0082c9", "#ffe36e", "#10204a", "#c98879", "#00ff00", "#888888"] {
            for ground in [light, dark] {
                guard let accent = ServerAccent.legible(hex: hex, on: ground) else { continue }
                let ink: ServerAccent.RGB =
                    ServerAccent.contrast(.white, accent) >= ServerAccent.contrast(.black, accent)
                    ? .white : .black
                #expect(
                    ServerAccent.contrast(ink, accent) >= ServerAccent.minimumContrast,
                    "\(hex) on \(ground) carries no legible text")
            }
        }
    }

    @Test("The server's own text colour is honoured only where it passes")
    func honoursServerTextColour() throws {
        let yellow = try #require(ServerAccent.components(hex: "#ffe36e"))
        // White on that yellow is 1.2:1. The server saying so does not make it
        // readable, so it is refused and the legible one used instead.
        #expect(ServerAccent.textColour(on: yellow, preferring: "#ffffff") == .black)
        #expect(ServerAccent.textColour(on: yellow, preferring: "#000000") == .black)

        let navy = try #require(ServerAccent.components(hex: "#10204a"))
        #expect(ServerAccent.textColour(on: navy, preferring: "#ffffff") == .white)
        #expect(ServerAccent.textColour(on: navy, preferring: nil) == .white)
    }

    @Test("Contrast is symmetric and bounded, as WCAG defines it")
    func contrastShape() {
        #expect(abs(ServerAccent.contrast(.white, .black) - 21) < 0.01)
        #expect(abs(ServerAccent.contrast(.black, .white) - 21) < 0.01)
        #expect(abs(ServerAccent.contrast(.white, .white) - 1) < 0.001)
    }
}
