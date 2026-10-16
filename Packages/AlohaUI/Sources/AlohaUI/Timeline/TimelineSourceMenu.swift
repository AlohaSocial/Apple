// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI
import TipKit

/// Which of the three timelines you are reading — My feed, Local, Global —
/// chosen from the screen's title, the way Photos and Mail switch what a
/// screen shows.
///
/// It used to be two things at once: a glass segmented control that floated
/// up from the foot of the feed when you scrolled *down* and hid again four
/// seconds later, and the real picker behind a filter glyph in the overflow
/// menu. The title is always there, always says which timeline this is, and
/// is where the system puts exactly this choice.
struct TimelineSourceMenu: ViewModifier {
    @Binding var source: TimelineSource

    func body(content: Content) -> some View {
        #if os(tvOS) || os(watchOS)
            content
        #else
            content
                .toolbarTitleMenu {
                    Picker(selection: $source) {
                        ForEach(Self.options, id: \.source) { option in
                            Text(option.title).tag(option.source)
                        }
                    } label: {
                        Text("Timeline source", comment: "Accessibility label")
                    }
                }
                .onChange(of: source) {
                    TimelineSourceTip().invalidate(reason: .actionPerformed)
                }
                // Once, inline, above the posts: a title menu is not
                // something people look for until they are told it is there.
                .safeAreaBar(edge: .top, spacing: 0) {
                    TipView(TimelineSourceTip())
                        .padding(.horizontal, AlohaMetrics.space4)
                }
        #endif
    }

    static let options: [(source: TimelineSource, title: LocalizedStringResource)] = [
        (.home, LocalizedStringResource("My feed", comment: "Timeline source")),
        (.local, LocalizedStringResource("Local", comment: "Timeline source")),
        (.federated, LocalizedStringResource("Global", comment: "Timeline source")),
    ]
}
