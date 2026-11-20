// SPDX-License-Identifier: MIT

import AlohaMedia
import AppIntents
import SwiftUI
import WidgetKit

/// The upload's Cancel button names an intent from `AlohaMedia`; listing the
/// package puts it in this extension's App Intents metadata, which a package's
/// types are otherwise left out of.
struct AlohaWidgetsAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [AlohaMediaAppIntents.self] }
}

#if os(iOS)
    import ActivityKit

    /// The upload's Live Activity. Work in progress, not content (docs/09 §9).
    ///
    /// On a paired Apple Watch it shows in the Smart Stack too, in the small
    /// family: what is happening and how far along, with no Cancel — a tap
    /// there opens the activity on the watch, not the intent.
    struct UploadLiveActivity: Widget {
        var body: some WidgetConfiguration {
            ActivityConfiguration(for: UploadActivityAttributes.self) { context in
                UploadActivityContent(state: context.state) { lockScreen($0) }
                    .activityBackgroundTint(.black.opacity(0.6))
            } dynamicIsland: { context in
                DynamicIsland {
                    DynamicIslandExpandedRegion(.leading) {
                        Image(systemName: Self.symbol(context.state))
                            .font(.title2)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    DynamicIslandExpandedRegion(.center) {
                        Text(title(context.state)).font(.caption)
                    }
                    DynamicIslandExpandedRegion(.trailing) {
                        cancelButton(context.state)
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
                    Image(systemName: Self.symbol(context.state))
                } compactTrailing: {
                    if context.state.phase == .uploading {
                        Text(
                            context.state.fraction,
                            format: .percent.precision(.fractionLength(0))
                        )
                        .font(.caption2.monospacedDigit())
                    }
                } minimal: {
                    Image(systemName: Self.symbol(context.state))
                }
            }
            .supplementalActivityFamilies([.small])
        }

        private func lockScreen(
            _ state: UploadActivityAttributes.ContentState
        ) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label {
                        Text(title(state))
                    } icon: {
                        Image(systemName: Self.symbol(state))
                    }
                    .font(.caption.weight(.medium))

                    Spacer()

                    if state.phase == .uploading {
                        Text(verbatim: "\(state.completed)/\(state.total)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    cancelButton(state)
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

        /// Cancel while bytes are going up, and only then (docs/09 §9): a
        /// transcode is the server's and cannot be called back from here, and
        /// a post being sent may already be out.
        @ViewBuilder
        private func cancelButton(_ state: UploadActivityAttributes.ContentState) -> some View {
            if state.phase == .uploading {
                Button(intent: CancelUploadIntent()) {
                    Label {
                        Text("Cancel", comment: "Live Activity button that stops the upload")
                    } icon: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text("Cancel upload", comment: "Live Activity button, accessibility label"))
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

        static func symbol(_ state: UploadActivityAttributes.ContentState) -> String {
            switch state.phase {
            case .uploading, .posting: "arrow.up.circle"
            case .processing: "gearshape.arrow.triangle.2.circlepath"
            case .ready: "checkmark.circle"
            case .posted: "checkmark.circle.fill"
            case .failed: "exclamationmark.triangle"
            }
        }
    }

    /// The Lock Screen's layout, or the watch's where the system asks for the
    /// small family.
    struct UploadActivityContent<LockScreen: View>: View {
        @Environment(\.activityFamily) private var family
        let state: UploadActivityAttributes.ContentState
        @ViewBuilder let lockScreen: (UploadActivityAttributes.ContentState) -> LockScreen

        var body: some View {
            if family == .small {
                UploadSmallView(state: state)
                    .padding(8)
            } else {
                lockScreen(state)
                    .padding()
            }
        }
    }

    /// The watch's Smart Stack: a few words and a bar, at a glance from the
    /// wrist. The phone's titles are sentences, too long for the space.
    struct UploadSmallView: View {
        let state: UploadActivityAttributes.ContentState

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(title)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: UploadLiveActivity.symbol(state))
                }
                .font(.headline)
                switch state.phase {
                case .uploading:
                    ProgressView(value: state.fraction)
                        .progressViewStyle(.linear)
                    Text(verbatim: "\(state.completed)/\(state.total)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                case .processing, .posting:
                    ProgressView().progressViewStyle(.linear)
                case .ready, .posted, .failed:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var title: String {
            switch state.phase {
            case .uploading:
                String(localized: "Uploading", comment: "Watch Live Activity title, short")
            case .processing:
                String(
                    localized: "Processing",
                    comment: "Watch Live Activity title, short: the server transcodes a video")
            case .ready:
                String(
                    localized: "Ready to post",
                    comment: "Live Activity title, uploads done and waiting for Post")
            case .posting: String(localized: "Posting…", comment: "Live Activity title")
            case .posted: String(localized: "Posted", comment: "Live Activity title")
            case .failed: String(localized: "Upload failed", comment: "Live Activity title")
            }
        }
    }
#endif
