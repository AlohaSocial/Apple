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
}
