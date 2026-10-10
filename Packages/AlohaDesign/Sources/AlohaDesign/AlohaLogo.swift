// SPDX-License-Identifier: MIT

import SwiftUI

/// The app's lockup: its logo, its wordmark, and the one place those two
/// things appear together.
///
/// An app that shows a generic SF Symbol where its own logo should be looks
/// like a prototype of itself. The logo lives in this package's asset catalog
/// so every target — iOS, iPad, Mac, the widgets — draws the same mark without
/// the app target's bundle being reachable from a package.
public struct AlohaLogo: View {
    @Environment(\.alohaPalette) private var palette

    /// The full lockup: logo above the wordmark. For the first screen a person
    /// ever sees.
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Image("AlohaLogo", bundle: .module)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            AlohaWordmark()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Aloha Social", comment: "App name"))
    }
}

/// The name, in the brand's own type.
///
/// Rounded, because the logo is round and a wordmark that fights its own mark
/// reads as two different apps. The weight is heavy enough to hold against the
/// logo above it, and the tracking is tightened the way a wordmark is set by
/// hand rather than left at the default.
public struct AlohaWordmark: View {
    @Environment(\.alohaPalette) private var palette

    /// Scales with Dynamic Type like everything else: a wordmark that stays
    /// fixed while the rest of the screen grows is a bug at large text sizes.
    public init() {}

    public var body: some View {
        Text("Aloha Social", comment: "App name")
            .font(.system(.title, design: .rounded, weight: .bold))
            .tracking(-0.5)
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
