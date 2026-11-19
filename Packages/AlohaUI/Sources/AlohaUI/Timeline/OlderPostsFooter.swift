// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

/// The foot of a feed that has more: it asks for the next page as it comes
/// into view, and says so with a button where asking found nothing to show
/// — a media mode filtered here can go several pages without a match, and a
/// feed whose only trigger was a row appearing then stopped for good.
///
/// One view whatever it shows, so swapping the spinner for the button is not
/// a second appearance that asks again by itself.
struct OlderPostsFooter: View {
    @Environment(\.alohaPalette) private var palette
    let isLoading: Bool
    /// Off where the footer is not at the end of a scrolled list — under an
    /// empty state, say — and so would appear again every time the state
    /// around it changed, asking for page after page with nobody scrolling.
    var loadsOnAppear = true
    let load: () -> Void

    var body: some View {
        HStack {
            Spacer()
            if isLoading {
                ProgressView()
            } else {
                Button(action: load) {
                    Text("Load more posts", comment: "Feed footer: fetches older posts")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.vertical, AlohaMetrics.space3)
        .onAppear {
            if loadsOnAppear { load() }
        }
    }
}
