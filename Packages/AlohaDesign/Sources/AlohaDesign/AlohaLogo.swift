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
            AlohaLogoMark(size: 96)
            AlohaWordmark()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Aloha Social", comment: "App name"))
    }
}

/// The mark on its own, at any size: above a sign-in field, in an empty state,
/// or wherever the wordmark would be too much.
///
/// It lives here, in the design package, so no other package has to reach into
/// this one's asset catalog — an `Image(_:bundle:)` in another module resolves
/// against *that* module's resources and silently draws nothing.
public struct AlohaLogoMark: View {
    private let size: CGFloat

    public init(size: CGFloat = 96) {
        self.size = size
    }

    public var body: some View {
        Image("AlohaLogo", bundle: .module)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
