// SPDX-License-Identifier: MIT

import SwiftUI

/// The type scale.
///
/// The app had three sizes — a name, a body, a caption — so nothing inside a
/// screen established hierarchy; every block of text weighed the same as every
/// other. These are the six steps it actually needs, each with a job.
///
/// All of them are relative to the person's Dynamic Type setting: the sizes
/// below are the *default* metrics, not fixed points.
public enum AlohaType {
    /// The one thing a screen is about: a profile's name, a focused post.
    public static var display: Font { .system(.title2, design: .default, weight: .bold) }

    /// A section's own heading, inside a screen rather than in the bar.
    public static var section: Font { .system(.subheadline, weight: .semibold) }

    /// Who wrote this.
    public static var name: Font { .system(.subheadline, weight: .semibold) }

    /// What they wrote. Serif is a reading preference, so it is resolved with
    /// the metrics rather than here.
    public static func body(serif: Bool) -> Font {
        serif ? .system(.body, design: .serif) : .body
    }

    /// The handle, the age, the counts — present but never competing.
    public static var meta: Font { .system(.caption, design: .rounded) }

    /// Badges and overlays, where space is the constraint.
    public static var micro: Font { .system(.caption2, weight: .medium) }

    /// The app's own name, where it is set large: the onboarding hero, the
    /// sign-in screen, the empty state before there is an account.
    ///
    /// Rounded and tightly tracked, because the logo it sits under is round —
    /// a wordmark that fights its own mark reads as two different apps. The
    /// repository carries no brand font file, so this is the system's rounded
    /// design rather than a bundled typeface; if the brand's own font arrives,
    /// this one function and the `Info.plist` `UIAppFonts` entry are the only
    /// two places that change.
    public static var wordmark: Font {
        .system(.title, design: .rounded, weight: .bold)
    }

    /// The tracking the wordmark is set with, the way a logotype is set by
    /// hand rather than left at the default.
    public static let wordmarkTracking: CGFloat = -0.5
}
