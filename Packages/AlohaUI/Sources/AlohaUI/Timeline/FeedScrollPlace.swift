// SPDX-License-Identifier: MIT

import SwiftUI

extension View {
    /// Keeps a feed's place in a `ScrollView` on its model, and goes back to
    /// it when the screen is built again over the same model (`FeedModels`).
    ///
    /// The `List` timeline does this itself (`TimelineView`); the media feeds
    /// are scroll views over a lazy stack or grid, which must carry
    /// `.scrollTargetLayout()` for their rows to be the positions reported.
    func keepsFeedPlace(_ model: TimelineModel) -> some View {
        modifier(FeedScrollPlace(model: model))
    }
}

private struct FeedScrollPlace: ViewModifier {
    let model: TimelineModel
    @State private var position: String?
    /// Read once, when the screen is first built: the rows of the new screen
    /// report themselves as they appear, and the place to return to is the
    /// one the reader left, not the top of the new list.
    @State private var resumeAnchorID: String?

    init(model: TimelineModel) {
        self.model = model
        _resumeAnchorID = State(initialValue: model.rows.isEmpty ? nil : model.readingAnchorID)
    }

    func body(content: Content) -> some View {
        content
            .scrollPosition(id: $position, anchor: .top)
            .onChange(of: position) { _, id in
                if let id { model.readingAnchorID = id }
            }
            .onAppear {
                guard let anchor = resumeAnchorID else { return }
                resumeAnchorID = nil
                // A turn later, so the stack has laid out the rows to
                // scroll to.
                Task { @MainActor in
                    await Task.yield()
                    position = anchor
                }
            }
    }
}
