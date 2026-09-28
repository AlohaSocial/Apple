// SPDX-License-Identifier: MIT

import AlohaMedia
import SwiftUI
import WidgetKit

#if os(iOS)
    import ActivityKit

    /// The upload's Live Activity. Work in progress, not content (docs/09 §9).
    struct UploadLiveActivity: Widget {
        var body: some WidgetConfiguration {
            ActivityConfiguration(for: UploadActivityAttributes.self) { context in
                lockScreen(context.state)
                    .padding()
                    .activityBackgroundTint(.black.opacity(0.6))
            } dynamicIsland: { context in
                DynamicIsland {
                    DynamicIslandExpandedRegion(.leading) {
                        Image(
                            systemName: context.state.failed
                                ? "exclamationmark.triangle" : "arrow.up.circle"
                        )
                        .font(.title2)
                    }
                    DynamicIslandExpandedRegion(.center) {
                        Text(title(context.state)).font(.caption)
                    }
                    DynamicIslandExpandedRegion(.bottom) {
                        ProgressView(value: context.state.fraction)
                            .progressViewStyle(.linear)
                    }
                } compactLeading: {
                    Image(systemName: "arrow.up.circle")
                } compactTrailing: {
                    Text(context.state.fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.caption2.monospacedDigit())
                } minimal: {
                    Image(systemName: "arrow.up.circle")
                }
            }
        }

        private func lockScreen(
            _ state: UploadActivityAttributes.ContentState
        ) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label {
                        Text(title(state))
                    } icon: {
                        Image(
                            systemName: state.failed
                                ? "exclamationmark.triangle" : "arrow.up.circle")
                    }
                    .font(.caption.weight(.medium))

                    Spacer()

                    if !state.isFinished {
                        Text(verbatim: "\(state.completed)/\(state.total)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if !state.isFinished {
                    ProgressView(value: state.fraction)
                        .progressViewStyle(.linear)
                    if !state.currentFilename.isEmpty {
                        Text(state.currentFilename)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }

        private func title(_ state: UploadActivityAttributes.ContentState) -> String {
            if state.failed {
                return String(localized: "Upload failed", comment: "Live Activity title")
            }
            if state.isFinished {
                return String(localized: "Upload finished", comment: "Live Activity title")
            }
            return String(localized: "Uploading media", comment: "Live Activity title")
        }
    }
#endif
