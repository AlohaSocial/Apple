// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI
import TipKit

/// Which timeline you are reading — My Feed, For you, Local, Global, the
/// scopes Nextcloud Social's own switcher offers — chosen from the screen's
/// title, the way Photos and Mail switch what a screen shows.
///
/// It used to be two things at once: a glass segmented control that floated
/// up from the foot of the feed when you scrolled *down* and hid again four
/// seconds later, and the real picker behind a filter glyph in the overflow
/// menu. The title is always there, always says which timeline this is, and
/// is where the system puts exactly this choice.
struct TimelineSourceMenu: ViewModifier {
    @Binding var source: TimelineSource
    /// For you is Nextcloud Social's; other servers have no such ranking.
    var offersForYou = false

    func body(content: Content) -> some View {
        #if os(tvOS) || os(watchOS)
            content
        #else
            content
                .toolbarTitleMenu {
                    Picker(selection: $source) {
                        ForEach(Self.options(offersForYou: offersForYou), id: \.source) {
                            option in
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

    static func options(
        offersForYou: Bool
    ) -> [(source: TimelineSource, title: LocalizedStringResource)] {
        var options: [(source: TimelineSource, title: LocalizedStringResource)] = [
            (.home, LocalizedStringResource("My Feed", comment: "Timeline source"))
        ]
        // Second, where the web app puts it.
        if offersForYou {
            options.append(
                (.interests, LocalizedStringResource("For you", comment: "Timeline source")))
        }
        options += [
            (.local, LocalizedStringResource("Local", comment: "Timeline source")),
            (.federated, LocalizedStringResource("Global", comment: "Timeline source")),
        ]
        return options
    }
}
