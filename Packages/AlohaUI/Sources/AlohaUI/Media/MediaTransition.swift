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
        #if os(iOS) || os(visionOS) || os(tvOS)
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
        #if os(iOS) || os(visionOS) || os(tvOS)
            if let namespace {
                navigationTransition(.zoom(sourceID: id, in: namespace))
            } else {
                self
            }
        #else
            self
        #endif
    }
}
