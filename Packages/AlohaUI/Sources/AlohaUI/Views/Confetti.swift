// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

/// Thrown once, the first time somebody posts from this app.
///
/// Once, deliberately: a celebration that fires on every post stops being one,
/// and the fediverse does not need another app that showers you in paper.
public enum FirstPost {
    private static let key = "aloha.hasPosted"

    public static var isStillToCome: Bool {
        !UserDefaults.standard.bool(forKey: key)
    }

    public static func recordPosted() {
        UserDefaults.standard.set(true, forKey: key)
    }
}

/// A short fall of paper in the app's own colours.
struct ConfettiView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isFalling: Bool

    private static let count = 34

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<Self.count, id: \.self) { index in
                    Piece(
                        index: index,
                        size: proxy.size,
                        colour: colour(index),
                        isFalling: isFalling && !reduceMotion)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func colour(_ index: Int) -> Color {
        [palette.accent, palette.boost, palette.favourite, palette.bookmark, palette.mention][
            index % 5]
    }

    private struct Piece: View {
        let index: Int
        let size: CGSize
        let colour: Color
        let isFalling: Bool

        /// Deterministic per piece, so a redraw does not reshuffle the fall.
        private var random: (x: Double, delay: Double, spin: Double, scale: Double) {
            var seed = UInt64(index &* 2_654_435_761)
            func next() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double((seed >> 33) % 1000) / 1000
            }
            return (next(), next() * 0.5, next(), 0.6 + next() * 0.7)
        }

        var body: some View {
            let values = random
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(colour)
                .frame(width: 7 * values.scale, height: 11 * values.scale)
                .rotationEffect(.degrees(isFalling ? 360 * (values.spin * 4 - 2) : 0))
                .position(
                    x: values.x * size.width,
                    y: isFalling ? size.height + 40 : -40
                )
                .opacity(isFalling ? 1 : 0)
                .animation(
                    .easeIn(duration: 2.1 + values.spin * 0.8).delay(values.delay),
                    value: isFalling)
        }
    }
}
