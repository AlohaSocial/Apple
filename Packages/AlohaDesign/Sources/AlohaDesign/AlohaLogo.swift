// SPDX-License-Identifier: MIT

import SwiftUI

/// The app's lockup: its logo, its wordmark, and the one place those two
/// things appear together.
///
/// An app that shows a generic SF Symbol where its own logo should be looks
/// like a prototype of itself. Shared vector geometry lets every target draw
/// the same mark without reaching into the app target's bundle.
public struct AlohaLogo: View {
    @Environment(\.alohaPalette) private var palette

    /// The full lockup: logo above the wordmark. For the first screen a person
    /// ever sees.
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            AnimatedAlohaLogoMark(size: 96)
            AlohaWordmark()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Aloha Social", comment: "App name"))
    }
}

/// The mark on its own, at any size: above a sign-in field, in an empty state,
/// or wherever the wordmark would be too much.
///
/// Native vector geometry stays crisp at any size and leaves the surrounding
/// surface visible in every theme. The paths follow the original brand SVG.
public struct AlohaLogoMark: View {
    private let size: CGFloat

    public init(size: CGFloat = 96) {
        self.size = size
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let bounds = CGRect(origin: .zero, size: canvasSize)
            context.fill(
                AlohaBrandPaths.flower(in: bounds),
                with: .color(Color(red: 232.0 / 255, green: 96.0 / 255, blue: 76.0 / 255)))
            context.fill(AlohaBrandPaths.glyph(in: bounds), with: .color(.white))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A quiet breathing mark while loading or welcoming, without delaying launch.
public struct AnimatedAlohaLogoMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false
    private let size: CGFloat

    public init(size: CGFloat = 96) { self.size = size }

    public var body: some View {
        AlohaLogoMark(size: size)
            .scaleEffect(reduceMotion ? 1 : (isAnimating ? 1.025 : 0.975))
            .rotationEffect(.degrees(reduceMotion ? 0 : (isAnimating ? 3 : -3)))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 2).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear { isAnimating = !reduceMotion }
            .onChange(of: reduceMotion) { _, reduced in isAnimating = !reduced }
    }
}

/// The name, in the brand's own type.
///
/// Rounded, because the logo is round and a wordmark that fights its own mark
/// reads as two different apps. The weight is heavy enough to hold against the
/// logo above it, and the tracking is tightened the way a logotype is set by
/// hand rather than left at the default.
///
/// The type face itself is one function away (`AlohaType.wordmark`): the
/// repository ships no brand font, and if the brand's own arrives, that
/// function and the `UIAppFonts` entry in the app's Info.plist are the only two
/// places that change.
public struct AlohaWordmark: View {
    @Environment(\.alohaPalette) private var palette

    /// Scales with Dynamic Type like everything else: a wordmark that stays
    /// fixed while the rest of the screen grows is a bug at large text sizes.
    public init() {}

    public var body: some View {
        Text("Aloha Social", comment: "App name")
            .font(AlohaType.wordmark)
            .tracking(AlohaType.wordmarkTracking)
            .foregroundStyle(palette.label)
    }
}

#Preview {
    VStack(spacing: 32) {
        AlohaLogo()
        AlohaWordmark()
    }
    .padding()
}
