// SPDX-License-Identifier: MIT

import SwiftUI

/// The colour the server wears, made safe to use as the app's accent.
///
/// An administrator's theming colour is whatever they typed. It can be a pale
/// yellow that vanishes on white or a navy that vanishes on black, and the app
/// draws small text and hairline glyphs in the accent — so the colour is taken
/// as an *intention* and moved until it is legible, rather than used raw or
/// thrown away.
///
/// Nextcloud already does most of this: it publishes the primary darkened for a
/// light background and lightened for a dark one. This is the backstop for the
/// servers that publish only `color`, for the ones whose variants still miss,
/// and for the app's own background, which is not the one Nextcloud computed
/// against (docs/05 §2).
public enum ServerAccent {
    /// WCAG AA for body text. The accent carries counts and timestamps at
    /// caption size, so the lower large-text threshold does not apply.
    public static let minimumContrast: Double = 4.5

    /// A hex string as a colour, or `nil` for anything that is not one.
    public static func colour(hex: String?) -> Color? {
        guard let rgb = components(hex: hex) else { return nil }
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    /// The server's colour, moved until it reads against this background.
    ///
    /// Lightness is walked toward or away from the background in small steps —
    /// the hue and the saturation are what make it *their* colour, so those are
    /// held and only the lightness gives. Twenty steps is enough to cross the
    /// whole range; a colour that still fails after them (a mid-grey on a
    /// mid-grey background) hands back `nil` so the caller keeps its own accent
    /// rather than drawing something nobody can read.
    ///
    /// Nextcloud's own default blue needs this: it is 4.0:1 on the app's light
    /// ground, which is close enough to look fine and far enough to fail.
    public static func legible(hex: String?, on background: RGB) -> RGB? {
        guard let start = components(hex: hex) else { return nil }
        return legibleComponents(start, on: background)
    }

    public static func colour(_ rgb: RGB) -> Color {
        Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    /// Black or white, whichever reads on the accent.
    ///
    /// Measured against the accent **after** the contrast guard has moved it,
    /// not against the colour the server sent: the guard darkens a colour on a
    /// light ground, which is exactly the change that decides this.
    ///
    /// Nextcloud's `color-text` is preferred where it passes — it is what the
    /// administrator's own buttons use, so agreeing with them is worth a step.
    public static func textColour(on accent: RGB, preferring preferred: String?) -> Color {
        if let wanted = components(hex: preferred),
            contrast(wanted, accent) >= minimumContrast
        {
            return Color(.sRGB, red: wanted.red, green: wanted.green, blue: wanted.blue, opacity: 1)
        }
        return contrast(.white, accent) >= contrast(.black, accent) ? .white : .black
    }

    // MARK: - Colour arithmetic

    /// sRGB in 0…1. `Color` cannot be read back portably, so the maths happens
    /// on this and the `Color` is only ever the last step.
    public struct RGB: Sendable, Hashable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        public static let white = RGB(red: 1, green: 1, blue: 1)
        public static let black = RGB(red: 0, green: 0, blue: 0)
    }

    public static func components(hex: String?) -> RGB? {
        guard var text = hex?.trimmingCharacters(in: .whitespaces).lowercased(), !text.isEmpty
        else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return RGB(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }

    /// WCAG relative luminance.
    public static func luminance(_ rgb: RGB) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.red) + 0.7152 * channel(rgb.green) + 0.0722 * channel(rgb.blue)
    }

    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let first = luminance(a)
        let second = luminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// Walks the colour away from the background until it reads, or gives up.
    static func legibleComponents(_ start: RGB, on background: RGB) -> RGB? {
        if contrast(start, background) >= minimumContrast { return start }

        // Toward black on a light background, toward white on a dark one:
        // moving the other way would have to cross the background to succeed.
        let towardBlack = luminance(background) > 0.5
        var current = start

        for _ in 0..<20 {
            current = towardBlack ? darkened(current) : lightened(current)
            if contrast(current, background) >= minimumContrast { return current }
        }
        return nil
    }

    private static func darkened(_ rgb: RGB) -> RGB {
        RGB(red: rgb.red * 0.88, green: rgb.green * 0.88, blue: rgb.blue * 0.88)
    }

    private static func lightened(_ rgb: RGB) -> RGB {
        RGB(
            red: rgb.red + (1 - rgb.red) * 0.12,
            green: rgb.green + (1 - rgb.green) * 0.12,
            blue: rgb.blue + (1 - rgb.blue) * 0.12)
    }
}
