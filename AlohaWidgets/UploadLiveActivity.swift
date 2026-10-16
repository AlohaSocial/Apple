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
                        Image(systemName: symbol(context.state))
                            .font(.title2)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    DynamicIslandExpandedRegion(.center) {
                        Text(title(context.state)).font(.caption)
                    }
                    DynamicIslandExpandedRegion(.bottom) {
                        if context.state.phase == .uploading {
                            ProgressView(value: context.state.fraction)
                                .progressViewStyle(.linear)
                        } else if context.state.phase == .processing
                            || context.state.phase == .posting
                        {
                            // No fraction to show: the server does not say
                            // how far along a transcode or a post is.
                            ProgressView().progressViewStyle(.linear)
                        }
                    }
                } compactLeading: {
                    Image(systemName: symbol(context.state))
                } compactTrailing: {
                    if context.state.phase == .uploading {
                        Text(
                            context.state.fraction,
                            format: .percent.precision(.fractionLength(0))
                        )
                        .font(.caption2.monospacedDigit())
                    }
                } minimal: {
                    Image(systemName: symbol(context.state))
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
                        Image(systemName: symbol(state))
                    }
                    .font(.caption.weight(.medium))

                    Spacer()

                    if state.phase == .uploading {
                        Text(verbatim: "\(state.completed)/\(state.total)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if state.phase == .processing || state.phase == .posting {
                    ProgressView().progressViewStyle(.linear)
                } else if state.phase == .uploading {
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
            switch state.phase {
            case .uploading:
                String(localized: "Uploading media", comment: "Live Activity title")
            case .processing:
                String(
                    localized: "Your server is processing the video",
                    comment: "Live Activity title, while the server transcodes an upload")
            case .ready:
                String(
                    localized: "Ready to post",
                    comment: "Live Activity title, uploads done and waiting for Post")
            case .posting: String(localized: "Posting…", comment: "Live Activity title")
            case .posted: String(localized: "Posted", comment: "Live Activity title")
            case .failed: String(localized: "Upload failed", comment: "Live Activity title")
            }
        }

        private func symbol(_ state: UploadActivityAttributes.ContentState) -> String {
            switch state.phase {
            case .uploading, .posting: "arrow.up.circle"
            case .processing: "gearshape.arrow.triangle.2.circlepath"
            case .ready: "checkmark.circle"
            case .posted: "checkmark.circle.fill"
            case .failed: "exclamationmark.triangle"
            }
        }
    }
#endif
