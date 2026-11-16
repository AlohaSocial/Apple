// SPDX-License-Identifier: MIT

import SwiftUI

/// The "New post" button growing into the composer, as the system's own
/// apps open what a toolbar button makes: the sheet zooms out of the glass
/// button that was tapped, and shrinks back into it when it closes.
///
/// iOS and iPadOS only: the Mac opens the composer as a window of its own
/// (docs/09 §2), and visionOS has no zoom from a toolbar item.
enum ComposeTransition {
    /// The one source the composer zooms from. Every place that draws the
    /// button uses it; only the one on screen is ever matched.
    static let sourceID = "compose-post"
}

extension EnvironmentValues {
    /// The shell's namespace for the compose zoom, read by the sheet that
    /// presents the composer, far from the toolbar that draws the button.
    @Entry var composeTransition: Namespace.ID?
}

/// The composer's half of the zoom: applied only when the sheet was opened
/// by the button — a reply or a quote comes from a post, not from it — and
/// never under Reduce Motion, where the sheet arrives the plain way.
struct ComposerZoom: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.composeTransition) private var namespace

    let fromButton: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
            if fromButton, !reduceMotion, let namespace {
                content.navigationTransition(
                    .zoom(sourceID: ComposeTransition.sourceID, in: namespace))
            } else {
                content
            }
        #else
            content
        #endif
    }
}
