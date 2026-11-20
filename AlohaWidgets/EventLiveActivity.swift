// SPDX-License-Identifier: MIT

import AlohaStore
import SwiftUI
import WidgetKit

#if os(iOS)
    import ActivityKit

    /// The countdowns to the account's own poll closing and its next
    /// scheduled post going out (docs/09 §9), on the Lock Screen and in the
    /// Dynamic Island. `Text(timerInterval:)` runs the clock by itself, so
    /// the app never pushes an update; once the moment passes the activity
    /// is stale, and says what happened rather than showing a frozen 0:00.
    /// On a paired Apple Watch the countdown is in the Smart Stack too, in
    /// the small family (`EventSmallView`).
    struct EventLiveActivity: Widget {
        var body: some WidgetConfiguration {
            ActivityConfiguration(for: EventActivityAttributes.self) { context in
                EventActivityContent(context: context)
                    .activityBackgroundTint(.black.opacity(0.6))
                    .widgetURL(Self.url(context.attributes))
            } dynamicIsland: { context in
                DynamicIsland {
                    DynamicIslandExpandedRegion(.leading) {
                        Image(systemName: Self.symbol(context.attributes.kind))
                            .font(.title2)
                            .accessibilityHidden(true)
                    }
                    DynamicIslandExpandedRegion(.trailing) {
                        EventCountdown(context: context)
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .frame(maxWidth: 80, alignment: .trailing)
                    }
                    DynamicIslandExpandedRegion(.center) {
                        Self.title(context)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    DynamicIslandExpandedRegion(.bottom) {
                        if !context.state.text.isEmpty {
                            Text(context.state.text)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                } compactLeading: {
                    Image(systemName: Self.symbol(context.attributes.kind))
                        .accessibilityLabel(Self.title(context))
                } compactTrailing: {
                    EventCountdown(context: context)
                        .font(.caption2.monospacedDigit())
                        .frame(maxWidth: 44)
                } minimal: {
                    Image(systemName: Self.symbol(context.attributes.kind))
                        .accessibilityLabel(Self.title(context))
                }
                .widgetURL(Self.url(context.attributes))
            }
            .supplementalActivityFamilies([.small])
        }

        static func symbol(_ kind: EventActivityAttributes.Kind) -> String {
            switch kind {
            case .pollCloses: "chart.bar.xaxis"
            case .scheduledPost: "calendar.badge.clock"
            }
        }

        /// What is counting down, or what happened once it has.
        static func title(_ context: ActivityViewContext<EventActivityAttributes>) -> Text {
            switch (context.attributes.kind, context.isStale) {
            case (.pollCloses, false):
                Text(
                    "Your poll closes soon",
                    comment:
                        "Live Activity title while the account's own poll counts down to closing")
            case (.pollCloses, true):
                Text("Your poll has closed", comment: "Live Activity title after the poll closed")
            case (.scheduledPost, false):
                Text(
                    "Your post goes out at \(context.state.at, style: .time)",
                    comment: "Live Activity title; the time a scheduled post will be published")
            case (.scheduledPost, true):
                Text(
                    "Your scheduled post has gone out",
                    comment: "Live Activity title after the scheduled post's time passed")
            }
        }

        /// The poll opens as its post; a scheduled post opens the scheduled
        /// list, since it has no post to open yet.
        static func url(_ attributes: EventActivityAttributes) -> URL? {
            switch attributes.kind {
            case .pollCloses:
                WidgetData.statusURL(accountID: attributes.accountID, statusID: attributes.itemID)
            case .scheduledPost:
                SnapshotData.url("scheduled", accountID: attributes.accountID)
            }
        }
    }

    /// The clock: minutes and seconds to the moment, counted by the system.
    struct EventCountdown: View {
        let context: ActivityViewContext<EventActivityAttributes>
        /// A timer's text is as wide as its longest reading; the phone sets
        /// it against the trailing edge, the watch reads it from the leading.
        var alignment: TextAlignment = .trailing

        var body: some View {
            if context.isStale || context.state.at <= Date() {
                Image(systemName: "checkmark")
                    .accessibilityLabel(
                        Text("Done", comment: "Live Activity, the countdown has finished"))
            } else {
                Text(
                    timerInterval: min(context.attributes.startedAt, Date())...context.state.at,
                    countsDown: true
                )
                .multilineTextAlignment(alignment)
            }
        }
    }

    /// The Lock Screen's layout, or the watch's where the system asks for the
    /// small family.
    struct EventActivityContent: View {
        @Environment(\.activityFamily) private var family
        let context: ActivityViewContext<EventActivityAttributes>

        var body: some View {
            if family == .small {
                EventSmallView(context: context)
                    .padding(8)
            } else {
                EventLockScreenView(context: context)
                    .padding()
            }
        }
    }

    /// The watch's Smart Stack: what is counting down in two words, the clock
    /// large enough to read at a glance, and one line of the post. The
    /// phone's title is a sentence with a time in it, too long for the space.
    struct EventSmallView: View {
        let context: ActivityViewContext<EventActivityAttributes>

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    title
                        .lineLimit(1)
                } icon: {
                    Image(systemName: EventLiveActivity.symbol(context.attributes.kind))
                }
                .font(.caption.weight(.semibold))
                EventCountdown(context: context, alignment: .leading)
                    .font(.title2.monospacedDigit().weight(.semibold))
                if !context.state.text.isEmpty {
                    Text(context.state.text)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var title: Text {
            switch (context.attributes.kind, context.isStale) {
            case (.pollCloses, false):
                Text("Poll closes", comment: "Watch Live Activity title, short")
            case (.pollCloses, true):
                Text("Poll closed", comment: "Watch Live Activity title, short")
            case (.scheduledPost, false):
                Text("Post goes out", comment: "Watch Live Activity title, short")
            case (.scheduledPost, true):
                Text("Post went out", comment: "Watch Live Activity title, short")
            }
        }
    }

    struct EventLockScreenView: View {
        let context: ActivityViewContext<EventActivityAttributes>

        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: EventLiveActivity.symbol(context.attributes.kind))
                    .font(.title2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    EventLiveActivity.title(context)
                        .font(.subheadline.weight(.semibold))
                    if !context.state.text.isEmpty {
                        Text(context.state.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                EventCountdown(context: context)
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .frame(maxWidth: 96, alignment: .trailing)
            }
        }
    }
#endif

#if os(iOS)
    /// Every Live Activity this extension draws, in a bundle of their own so
    /// the main bundle's builder stays inside its limit.
    struct LiveActivityWidgets: WidgetBundle {
        var body: some Widget {
            UploadLiveActivity()
            EventLiveActivity()
        }
    }
#endif
