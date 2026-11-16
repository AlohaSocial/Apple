// SPDX-License-Identifier: MIT

import SwiftUI

/// A list of settings-like rows: sections, a header, a line of explanation
/// under each.
///
/// On the Mac that is a grouped form — the look of System Settings — because
/// a plain `List` there draws a footer as a second bold header and a button
/// row as a stray control between two rules. Everywhere else it is the list
/// it always was.
struct GroupedList<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(macOS)
            Form(content: content)
                .formStyle(.grouped)
        #else
            List(content: content)
        #endif
    }
}
