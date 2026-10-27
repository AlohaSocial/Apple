// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

/// The posts that follow this one in a thread.
extension ComposerView {
    /// Each segment is its own text area; posting chains them.
    var threadEditor: some View {
        VStack(spacing: AlohaMetrics.space2) {
            ForEach(model.threadSegments.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: AlohaMetrics.space2) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundStyle(palette.tertiaryLabel)
                        .padding(.top, 6)
                    TextField(
                        text: Binding(
                            get: {
                                model.threadSegments.indices.contains(index)
                                    ? model.threadSegments[index] : ""
                            },
                            set: { value in
                                guard model.threadSegments.indices.contains(index) else { return }
                                model.threadSegments[index] = value
                            }),
                        prompt: Text("Continue the thread…", comment: "Thread segment placeholder"),
                        axis: .vertical
                    ) {
                        Text("Thread segment", comment: "Thread segment label")
                    }
                    .textFieldStyle(.plain)
                    Button {
                        model.removeThreadSegment(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.tertiaryLabel)
                    .accessibilityLabel(Text("Remove segment", comment: "Thread action"))
                }
            }
        }
        .padding(AlohaMetrics.space3)
        .background(palette.surfaceRaised)
    }
}
