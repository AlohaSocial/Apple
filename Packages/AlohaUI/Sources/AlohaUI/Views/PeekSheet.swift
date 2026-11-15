// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

/// What a peek shows: a route, named once so the sheet has an identity.
struct PeekedRoute: Identifiable {
    let id = UUID()
    let route: Route
}

/// A post, looked at over the list it came from: Space opens it, and Space,
/// Escape or a click on Done puts it away again, with the list where it was.
///
/// The Finder's Quick Look, for a timeline. Opening a post replaces the list
/// and coming back costs a scroll position on a bad day; a look does neither.
struct PeekSheet<Content: View>: View {
    @Environment(\.alohaPalette) private var palette

    @ViewBuilder let content: () -> Content
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: onClose) {
                            Text("Done", comment: "Dismisses a peek at a post")
                        }
                        .keyboardShortcut(.space, modifiers: [])
                    }
                }
        }
        .background(palette.background)
        #if os(macOS)
            .frame(minWidth: 560, idealWidth: 620, minHeight: 520, idealHeight: 680)
        #endif
        .onExitCommandIfAvailable(onClose)
    }
}

extension View {
    /// Escape on the Mac; nothing where there is no such key.
    @ViewBuilder
    fileprivate func onExitCommandIfAvailable(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
            onExitCommand(perform: action)
        #else
            self
        #endif
    }
}
