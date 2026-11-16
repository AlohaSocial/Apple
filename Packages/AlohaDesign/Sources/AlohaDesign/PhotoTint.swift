// SPDX-License-Identifier: MIT

import Foundation
import SwiftUI

/// A soft ground taken from a photograph's colours, the way Music tints its
/// player around the album art.
///
/// The colours are an intention, as the server's accent is (`ServerAccent`):
/// their hue is kept and their strength is not. A page that text sits on is
/// only *washed* with them — the theme's ground with a little of each colour
/// in it — and each wash is checked against the faintest text that will be
/// read on it, giving up strength until that text still reaches the 4.5:1
/// docs/12 §3 holds it to. A neon photograph makes a faintly warm or cool
/// page, never a neon one.
///
/// Pure arithmetic on `ServerAccent.RGB`, so it is tested without drawing.
public nonisolated struct PhotoTint: Sendable, Hashable {
    /// The grounds to draw, most prominent colour first; at least one.
    public let colours: [ServerAccent.RGB]
    /// Where the wash fades to: the theme's own ground for a page, a deeper
    /// shade of the first colour for a backdrop.
    public let base: ServerAccent.RGB

    /// The faintest text a page carries — timestamps, counts, handles — in
    /// light and in dark: the System theme's tertiary label, which the warm
    /// themes' own sit close to. A wash that keeps this legible keeps every
    /// darker (or, in dark mode, lighter) label legible too.
    public static func faintestText(isDark: Bool) -> ServerAccent.RGB {
        isDark
            ? ServerAccent.RGB(red: 0.60, green: 0.60, blue: 0.63)
            : ServerAccent.RGB(red: 0.42, green: 0.42, blue: 0.44)
    }

    /// What the body text keeps at the least: AAA, so a page read at length
    /// is never harder to read for its colour.
    public static let bodyContrast = 7.0

    /// A tinted page for text to sit on.
    ///
    /// - Parameters:
    ///   - swatches: the photograph's colours, most prominent first.
    ///   - ground: the theme's ground, as numbers (`AlohaPalette.backgroundComponents`).
    ///   - isDark: whether the page is read in dark mode — light text on it.
    public static func page(
        from swatches: [ServerAccent.RGB], ground: ServerAccent.RGB, isDark: Bool
    ) -> PhotoTint? {
        guard !swatches.isEmpty else { return nil }
        // Never asks more of the wash than the plain ground managed: a theme
        // whose faint text sits just under the floor is not the photograph's
        // fault.
        let faint = faintestText(isDark: isDark)
        let floor = min(ServerAccent.minimumContrast, ServerAccent.contrast(ground, faint))
        let text: ServerAccent.RGB = isDark ? .white : .black
        func reads(_ washed: ServerAccent.RGB) -> Bool {
            ServerAccent.contrast(washed, faint) >= floor
                && ServerAccent.contrast(washed, text) >= bodyContrast
        }

        let colours = swatches.prefix(3).map { swatch -> ServerAccent.RGB in
            // A middling version of the colour: its hue, its saturation
            // held back, and a lightness that suits a wash on this ground.
            var hsl = HSL(swatch)
            hsl.saturation = min(hsl.saturation, 0.6)
            hsl.lightness = isDark ? 0.45 : 0.6
            let colour = hsl.rgb

            var amount = isDark ? 0.26 : 0.2
            var washed = mix(ground, colour, amount)
            while !reads(washed), amount > 0.01 {
                amount *= 0.7
                washed = mix(ground, colour, amount)
            }
            return washed
        }
        return PhotoTint(colours: colours, base: ground)
    }

    /// A deep backdrop for a photograph shown on its own — the media viewer,
    /// whose controls are white on glass whatever the theme.
    public static func backdrop(from swatches: [ServerAccent.RGB]) -> PhotoTint? {
        guard !swatches.isEmpty else { return nil }
        let colours = swatches.prefix(3).map { swatch -> ServerAccent.RGB in
            var hsl = HSL(swatch)
            hsl.saturation = min(hsl.saturation, 0.55)
            hsl.lightness = min(hsl.lightness, 0.16)
            return hsl.rgb
        }
        // Darker still at the foot, where the page dots and a video's own
        // controls sit.
        let base = mix(colours[0], .black, 0.55)
        return PhotoTint(colours: colours, base: base)
    }

    /// The colour `index` of the wash, falling back to the first when the
    /// photograph had fewer.
    public func colour(_ index: Int) -> Color {
        ServerAccent.colour(colours[min(index, colours.count - 1)])
    }

    public var baseColour: Color { ServerAccent.colour(base) }

    // MARK: - Arithmetic

    static func mix(
        _ a: ServerAccent.RGB, _ b: ServerAccent.RGB, _ amount: Double
    ) -> ServerAccent.RGB {
        ServerAccent.RGB(
            red: a.red + (b.red - a.red) * amount,
            green: a.green + (b.green - a.green) * amount,
            blue: a.blue + (b.blue - a.blue) * amount)
    }

    /// Hue, saturation and lightness, for changing how strong a colour is
    /// without changing which colour it is.
    nonisolated struct HSL {
        var hue: Double
        var saturation: Double
        var lightness: Double

        init(_ rgb: ServerAccent.RGB) {
            let high = max(rgb.red, rgb.green, rgb.blue)
            let low = min(rgb.red, rgb.green, rgb.blue)
            lightness = (high + low) / 2
            let delta = high - low
            guard delta > 0 else {
                hue = 0
                saturation = 0
                return
            }
            saturation = delta / (1 - abs(2 * lightness - 1))
            switch high {
            case rgb.red: hue = ((rgb.green - rgb.blue) / delta).truncatingRemainder(dividingBy: 6)
            case rgb.green: hue = (rgb.blue - rgb.red) / delta + 2
            default: hue = (rgb.red - rgb.green) / delta + 4
            }
            hue = (hue * 60 + 360).truncatingRemainder(dividingBy: 360)
        }

        var rgb: ServerAccent.RGB {
            let chroma = (1 - abs(2 * lightness - 1)) * saturation
            let sector = hue / 60
            let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
            let (red, green, blue): (Double, Double, Double) =
                switch sector {
                case ..<1: (chroma, second, 0)
                case ..<2: (second, chroma, 0)
                case ..<3: (0, chroma, second)
                case ..<4: (0, second, chroma)
                case ..<5: (second, 0, chroma)
                default: (chroma, 0, second)
                }
            let offset = lightness - chroma / 2
            return ServerAccent.RGB(
                red: min(max(red + offset, 0), 1), green: min(max(green + offset, 0), 1),
                blue: min(max(blue + offset, 0), 1))
        }
    }
}

/// The wash itself: the photograph's colours across the top, settling into
/// the base lower down, as one still gradient behind the scrolling content.
///
/// Still on purpose — a ground that moved while somebody read over it would
/// be motion nobody asked for — and drawn once, so it costs a scrolling list
/// nothing per frame.
public struct PhotoTintGround: View {
    private let tint: PhotoTint

    public init(_ tint: PhotoTint) {
        self.tint = tint
    }

    public var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.45], [0.55, 0.4], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                tint.colour(0), tint.colour(0), tint.colour(1),
                tint.colour(2), tint.colour(1), tint.colour(0),
                tint.baseColour, tint.baseColour, tint.baseColour,
            ]
        )
        .accessibilityHidden(true)
    }
}
