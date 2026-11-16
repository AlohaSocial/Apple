// SPDX-License-Identifier: MIT

import SwiftUI

extension View {
    /// What a screen is narrowed to — a source, a kind, read or unread — as
    /// one control in one place on the Mac: a segmented picker in the centre
    /// of the window's toolbar.
    ///
    /// Each screen used to bring its own: glass pills on Activities, a
    /// switch in a band on Direct messages, a second row on Discover. On the
    /// Mac they are the same question, and a toolbar has the width to ask it
    /// the same way every time. Elsewhere this does nothing, and each screen
    /// keeps the control that fits a phone.
    @ViewBuilder
    func toolbarFilter<Value: Hashable>(
        _ label: Text, selection: Binding<Value>, options: [(value: Value, title: String)]
    ) -> some View {
        #if os(macOS)
            modifier(ToolbarFilter(label: label, selection: selection, options: options))
        #else
            self
        #endif
    }
}

extension EnvironmentValues {
    /// Whether a screen is one of several sharing a window's toolbar — a
    /// column of the Mac's multi-column view — and so keeps its filter out
    /// of it: three filters in one toolbar's centre say nothing about which
    /// column each belongs to.
    @Entry var sharesToolbar = false
}

#if os(macOS)
    private struct ToolbarFilter<Value: Hashable>: ViewModifier {
        @Environment(\.sharesToolbar) private var sharesToolbar

        let label: Text
        let selection: Binding<Value>
        let options: [(value: Value, title: String)]

        func body(content: Content) -> some View {
            if sharesToolbar {
                content
            } else {
                content.toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker(selection: selection) {
                            ForEach(options, id: \.value) { option in
                                Text(verbatim: option.title).tag(option.value)
                            }
                        } label: {
                            label
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .help(label)
                    }
                }
            }
        }
    }
#endif
