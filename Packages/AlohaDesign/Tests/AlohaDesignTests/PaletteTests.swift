// SPDX-License-Identifier: MIT

import SwiftUI
import Testing

@testable import AlohaDesign

@Suite("Design tokens")
@MainActor
struct PaletteTests {

    /// Every role has to resolve in light, dark and both increased-contrast
    /// variants — that is what makes a theme change one edit rather than four
    /// (docs/05 §2).
    @Test("Every role resolves in all four appearances")
    func allRolesResolve() {
        let roles: [(String, KeyPath<AlohaPalette, Color>)] = [
            ("background", \.background), ("surface", \.surface),
            ("surfaceRaised", \.surfaceRaised), ("separator", \.separator),
            ("label", \.label), ("secondaryLabel", \.secondaryLabel),
            ("tertiaryLabel", \.tertiaryLabel), ("accent", \.accent),
            ("accentMuted", \.accentMuted), ("destructive", \.destructive),
            ("boost", \.boost), ("favourite", \.favourite),
            ("bookmark", \.bookmark), ("mention", \.mention), ("hashtag", \.hashtag),
        ]

        for theme in AlohaTheme.allCases {
            for scheme in [ColorScheme.light, .dark] {
                for contrast in [false, true] {
                    let palette = theme.palette(for: scheme, increaseContrast: contrast)
                    for (name, path) in roles {
                        let resolved = palette[keyPath: path].resolve(in: .init())
                        #expect(
                            resolved.opacity > 0,
                            "\(theme.rawValue)/\(scheme)/\(contrast) has no \(name)")
                    }
                }
            }
        }
    }

    /// Boost, favourite and bookmark must stay apart at badge size, including
    /// for readers with a colour-vision deficiency. The state also changes
    /// weight, so colour is never the only signal — this pins the colour half.
    @Test("Action tints stay distinguishable from each other")
    func actionTintsAreDistinct() {
        for theme in AlohaTheme.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let palette = theme.palette(for: scheme)
                let tints = [palette.boost, palette.favourite, palette.bookmark]
                    .map { $0.resolve(in: .init()) }

                for first in 0..<tints.count {
                    for second in (first + 1)..<tints.count {
                        #expect(
                            distance(tints[first], tints[second]) > 0.15,
                            "\(theme.rawValue)/\(scheme) tints \(first) and \(second) are too close"
                        )
                    }
                }
            }
        }
    }

    /// Every colour the app ever draws small text in, against the ground it is
    /// drawn on.
    ///
    /// This used to check `label` alone, which is the one role that was never
    /// in doubt. Apple's accessibility audit found `tertiaryLabel` at 3.09:1 in
    /// the warm light theme — handles, timestamps and badges, on every screen.
    @Test("Text roles meet WCAG AA against their background in every theme")
    func textRolesContrast() {
        for theme in AlohaTheme.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let palette = theme.palette(for: scheme)
                let roles: [(String, Color)] = [
                    ("label", palette.label),
                    ("secondaryLabel", palette.secondaryLabel),
                    ("tertiaryLabel", palette.tertiaryLabel),
                    ("accent", palette.accent),
                    ("destructive", palette.destructive),
                    ("mention", palette.mention),
                    ("hashtag", palette.hashtag),
                ]
                for (name, colour) in roles {
                    let ratio = contrast(colour, palette.background)
                    // WCAG AA for body text.
                    #expect(
                        ratio >= 4.5,
                        "\(theme.rawValue)/\(scheme) \(name) is \(ratio) against background")
                }
            }
        }
    }

    /// Text on the accent, which is what every prominent button is. A light
    /// accent on a dark theme takes dark text, so this checks `onAccent`
    /// rather than assuming white.
    @Test("Text on the accent meets WCAG AA")
    func accentCarriesItsText() {
        for theme in AlohaTheme.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let palette = theme.palette(for: scheme)
                let ratio = contrast(palette.onAccent, palette.accent)
                #expect(
                    ratio >= 4.5,
                    "\(theme.rawValue)/\(scheme) accent is \(ratio) under its own text colour")
            }
        }
    }

    private func contrast(_ first: Color, _ second: Color) -> Double {
        let a = luminance(first.resolve(in: .init()))
        let b = luminance(second.resolve(in: .init()))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    @Test("A theme's preferred scheme matches its palette")
    func schemeMatchesPalette() {
        #expect(AlohaTheme.system.preferredColorScheme == nil)
        #expect(AlohaTheme.warmLight.preferredColorScheme == .light)
        #expect(AlohaTheme.black.preferredColorScheme == .dark)
    }

    // MARK: - Helpers

    private func distance(_ first: Color.Resolved, _ second: Color.Resolved) -> Float {
        let red = first.red - second.red
        let green = first.green - second.green
        let blue = first.blue - second.blue
        return (red * red + green * green + blue * blue).squareRoot()
    }

    private func luminance(_ colour: Color.Resolved) -> Double {
        func channel(_ value: Float) -> Double {
            let value = Double(value)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(colour.red) + 0.7152 * channel(colour.green)
            + 0.0722 * channel(colour.blue)
    }
}
