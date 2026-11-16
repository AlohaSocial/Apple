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
            toolbar {
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
        #else
            self
        #endif
    }
}
