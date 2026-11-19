// SPDX-License-Identifier: MIT

import SwiftUI

/// The namespace that lets a photo fly out of the grid and back into it.
///
/// One namespace for the whole shell, because the source (a cell in a timeline
/// row or in the Photos grid) and the destination (the viewer, presented from
/// the shell) are far apart in the view tree.
extension EnvironmentValues {
    @Entry public var mediaTransition: Namespace.ID?
}

extension View {
    /// Marks this view as where the viewer should appear to come from.
    @ViewBuilder
    public func mediaTransitionSource(id: String, in namespace: Namespace.ID?) -> some View {
        #if os(iOS) || os(visionOS)
            if let namespace {
                matchedTransitionSource(id: id, in: namespace)
            } else {
                self
            }
        #else
            self
        #endif
    }

    /// Flies in from the matching source instead of cutting.
    @ViewBuilder
    public func mediaTransitionDestination(id: String, in namespace: Namespace.ID?) -> some View {
        #if os(iOS) || os(visionOS)
            if let namespace {
                navigationTransition(.zoom(sourceID: id, in: namespace))
            } else {
                self
            }
        #elseif os(macOS)
            // The Mac has no zoom transition, and its viewer is a sheet: the
            // picture settles into place inside it instead of being there
            // all at once.
            modifier(MediaSettleIn())
        #else
            self
        #endif
    }
}

#if os(macOS)
    private struct MediaSettleIn: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hasSettled = false

        func body(content: Content) -> some View {
            content
                .scaleEffect(hasSettled || reduceMotion ? 1 : 0.94)
                .opacity(hasSettled ? 1 : 0)
                .onAppear {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        hasSettled = true
                    }
                }
        }
    }
#endif
