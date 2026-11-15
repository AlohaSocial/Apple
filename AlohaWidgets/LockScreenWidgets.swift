// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaStore
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Direct messages

/// Unread direct messages: a count on the Lock Screen, and who sent them
/// where there is room. Names hide while the phone is locked.
struct DirectMessagesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SnapshotWidgetKind.directMessages.kind, intent: NotificationsWidgetAccount.self,
            provider: SnapshotProvider(kind: .directMessages)
        ) { entry in
            DirectMessagesView(entry: entry)
                .serverTint(entry.serverTheme)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.url("conversations"))
        }
        .configurationDisplayName(Text("Direct messages", comment: "Widget name"))
        .description(Text("Unread messages, and who sent them.", comment: "Widget description"))
        .supportedFamilies([.systemSmall] + SnapshotData.lockScreenCountFamilies)
    }
}

struct DirectMessagesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var unread: Int { entry.snapshot?.messages?.unread ?? 0 }

    /// The senders of the unread conversations, newest first.
    private var senders: [String] {
        (entry.snapshot?.messages?.conversations ?? []).filter(\.unread).map(\.names)
    }

    var body: some View {
        switch family {
        #if os(iOS)
            case .accessoryInline:
                Label {
                    Text("^[\(unread) unread message](inflect: true)", comment: "Widget text")
                } icon: {
                    Image(systemName: AlohaSymbol.directMessageFilled)
                }
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: AlohaSymbol.directMessageFilled)
                            .font(.caption)
                            .widgetAccentable()
                        Text(unread, format: .number)
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .contentTransition(.numericText())
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    Text("^[\(unread) unread message](inflect: true)", comment: "Widget text"))
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 0) {
                    Label {
                        Text("Messages", comment: "Lock Screen widget heading")
                    } icon: {
                        Image(systemName: AlohaSymbol.directMessageFilled)
                    }
                    .font(.headline)
                    .widgetAccentable()
                    Text("\(unread) unread", comment: "Lock Screen widget count")
                        .font(.body.monospacedDigit())
                    if !senders.isEmpty {
                        Text(senders.prefix(2).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .privacySensitive()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        #endif
        default:
            if entry.snapshot?.messages == nil {
                SnapshotPlaceholder(
                    symbol: AlohaSymbol.directMessage, text: SnapshotPlaceholder.openApp)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Image(systemName: AlohaSymbol.directMessageFilled)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .widgetAccentable()
                    Text(unread, format: .number)
                        .font(.largeTitle.weight(.bold))
                        .contentTransition(.numericText())
                    Text("unread messages", comment: "Widget label")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let first = senders.first {
                        Text(first)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .privacySensitive()
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Next scheduled post

/// The next post waiting to go out, with a countdown that runs on its own.
struct NextScheduledPostWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SnapshotWidgetKind.scheduled.kind, intent: NotificationsWidgetAccount.self,
            provider: SnapshotProvider(kind: .scheduled)
        ) { entry in
            NextScheduledPostView(entry: entry)
                .serverTint(entry.serverTheme)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.url("scheduled"))
        }
        .configurationDisplayName(Text("Next scheduled post", comment: "Widget name"))
        .description(
            Text("A countdown to the next post you scheduled.", comment: "Widget description")
        )
        .supportedFamilies([.systemSmall] + SnapshotData.lockScreenTextFamilies)
    }
}

struct NextScheduledPostView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var next: WidgetSnapshot.ScheduledPost? {
        entry.snapshot?.scheduled?.first { $0.at > entry.date }
    }

    var body: some View {
        switch family {
        #if os(iOS)
            case .accessoryInline:
                if let next {
                    Label {
                        Text(
                            "Post \(Text(next.at, style: .relative))",
                            comment: "Lock Screen inline: time until the next scheduled post")
                    } icon: {
                        Image(systemName: "clock.badge")
                    }
                } else {
                    Label {
                        Text("Nothing scheduled", comment: "Widget text")
                    } icon: {
                        Image(systemName: "clock")
                    }
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 0) {
                    Label {
                        Text("Next post", comment: "Lock Screen widget heading")
                    } icon: {
                        Image(systemName: "clock.badge")
                    }
                    .font(.headline)
                    .widgetAccentable()
                    if let next {
                        countdown(to: next.at)
                            .font(.body.monospacedDigit())
                        Text(next.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .privacySensitive()
                    } else {
                        Text("Nothing scheduled", comment: "Widget text")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        #endif
        default:
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeading(
                    symbol: "clock.badge", title: Text("Next post", comment: "Widget heading"))
                if let next {
                    countdown(to: next.at)
                        .font(.title2.weight(.bold).monospacedDigit())
                    Text(next.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .privacySensitive()
                    if next.mediaCount > 0 {
                        Label {
                            Text(
                                "^[\(next.mediaCount) attachment](inflect: true)",
                                comment: "Scheduled post widget")
                        } icon: {
                            Image(systemName: AlohaSymbol.media)
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                } else if entry.snapshot?.scheduled == nil {
                    SnapshotPlaceholder.openApp
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Nothing scheduled", comment: "Widget text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A live countdown within a day; further out, the day and time, since a
    /// countdown of 40 hours reads as noise.
    @ViewBuilder
    private func countdown(to date: Date) -> some View {
        if date.timeIntervalSince(entry.date) < 86_400 {
            Text(timerInterval: entry.date...date, countsDown: true)
        } else {
            Text(date, format: .dateTime.weekday(.abbreviated).hour().minute())
        }
    }
}

// MARK: - Requests

// Requests, reports and weekly stats live on the iPhone's Lock Screen only.
#if os(iOS)

    /// Follow requests and message requests waiting for a decision.
    struct RequestsWidget: Widget {
        var body: some WidgetConfiguration {
            AppIntentConfiguration(
                kind: SnapshotWidgetKind.requests.kind, intent: NotificationsWidgetAccount.self,
                provider: SnapshotProvider(kind: .requests)
            ) { entry in
                RequestsView(entry: entry)
                    .serverTint(entry.serverTheme)
                    .containerBackground(.fill.tertiary, for: .widget)
                    .widgetURL(RequestsView.destination(entry))
            }
            .configurationDisplayName(Text("Requests", comment: "Widget name"))
            .description(
                Text(
                    "Follow requests and message requests waiting for you.",
                    comment: "Widget description")
            )
            .supportedFamilies(SnapshotData.lockScreenCountFamilies)
        }
    }

    struct RequestsView: View {
        @Environment(\.widgetFamily) private var family
        let entry: SnapshotEntry

        private var follows: Int { entry.snapshot?.followRequests ?? 0 }
        private var messages: Int { entry.snapshot?.notificationRequests ?? 0 }
        private var total: Int { follows + messages }

        /// Follow requests first, since they are the ones somebody is waiting on.
        static func destination(_ entry: SnapshotEntry) -> URL? {
            let follows = entry.snapshot?.followRequests ?? 0
            let messages = entry.snapshot?.notificationRequests ?? 0
            return entry.url(
                follows > 0 || messages == 0 ? "follow-requests" : "notification-requests")
        }

        var body: some View {
            switch family {
            case .accessoryInline:
                Label {
                    if total == 0 {
                        Text("No requests", comment: "Widget text")
                    } else {
                        Text("^[\(total) request](inflect: true)", comment: "Widget text")
                    }
                } icon: {
                    Image(systemName: "person.badge.plus")
                }
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: total == 0 ? "checkmark" : "person.badge.plus")
                            .font(.caption)
                            .widgetAccentable()
                        if total > 0 {
                            Text(total, format: .number)
                                .font(.title3.weight(.semibold).monospacedDigit())
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    Text("^[\(total) request](inflect: true)", comment: "Widget text"))
            default:
                VStack(alignment: .leading, spacing: 0) {
                    Label {
                        Text("Requests", comment: "Lock Screen widget heading")
                    } icon: {
                        Image(systemName: "person.badge.plus")
                    }
                    .font(.headline)
                    .widgetAccentable()
                    if total == 0 {
                        Text("Nothing waiting", comment: "Requests widget, none")
                            .foregroundStyle(.secondary)
                    } else {
                        if follows > 0 {
                            Text(
                                "^[\(follows) follow request](inflect: true)",
                                comment: "Widget text")
                        }
                        if messages > 0 {
                            Text(
                                "^[\(messages) message request](inflect: true)",
                                comment: "Widget text: filtered notification requests")
                        }
                    }
                }
                .font(.body.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Open reports

    /// The moderator's queue: unresolved reports on the account's server.
    struct OpenReportsWidget: Widget {
        var body: some WidgetConfiguration {
            AppIntentConfiguration(
                kind: SnapshotWidgetKind.reports.kind, intent: NotificationsWidgetAccount.self,
                provider: SnapshotProvider(kind: .reports)
            ) { entry in
                OpenReportsView(entry: entry)
                    .serverTint(entry.serverTheme)
                    .containerBackground(.fill.tertiary, for: .widget)
                    .widgetURL(entry.url("reports"))
            }
            .configurationDisplayName(Text("Open reports", comment: "Widget name"))
            .description(
                Text(
                    "Reports waiting for a moderator on your server.", comment: "Widget description"
                )
            )
            .supportedFamilies(SnapshotData.lockScreenCountFamilies)
        }
    }

    struct OpenReportsView: View {
        @Environment(\.widgetFamily) private var family
        let entry: SnapshotEntry

        /// Nil where the account does not moderate, or the server has no panel.
        private var open: Int? { entry.snapshot?.openReports }

        var body: some View {
            switch family {
            case .accessoryInline:
                Label {
                    if let open {
                        Text("^[\(open) open report](inflect: true)", comment: "Widget text")
                    } else {
                        Text("Not a moderator", comment: "Reports widget, no access")
                    }
                } icon: {
                    Image(systemName: AlohaSymbol.report)
                }
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: open == 0 ? "checkmark" : "flag.fill")
                            .font(.caption)
                            .widgetAccentable()
                        if let open, open > 0 {
                            Text(open, format: .number)
                                .font(.title3.weight(.semibold).monospacedDigit())
                        } else if open == nil {
                            Text(verbatim: "–")
                                .font(.title3)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label)
            default:
                VStack(alignment: .leading, spacing: 0) {
                    Label {
                        Text("Reports", comment: "Lock Screen widget heading")
                    } icon: {
                        Image(systemName: "flag.fill")
                    }
                    .font(.headline)
                    .widgetAccentable()
                    label
                        .font(.body.monospacedDigit())
                        .foregroundStyle(open == nil ? .secondary : .primary)
                    Text(entry.accountHandle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        private var label: Text {
            switch open {
            case nil: Text("Not a moderator", comment: "Reports widget, no access")
            case 0: Text("All clear", comment: "Reports widget, none open")
            case let count?: Text("^[\(count) open report](inflect: true)", comment: "Widget text")
            }
        }
    }

    // MARK: - Weekly stats

    /// This week at a glance: new followers, and on Aloha Social servers how the
    /// week's favourites, boosts and replies compare with last week's.
    struct WeeklyStatsWidget: Widget {
        var body: some WidgetConfiguration {
            AppIntentConfiguration(
                kind: SnapshotWidgetKind.weeklyStats.kind, intent: NotificationsWidgetAccount.self,
                provider: SnapshotProvider(kind: .weeklyStats)
            ) { entry in
                WeeklyStatsView(entry: entry)
                    .serverTint(entry.serverTheme)
                    .containerBackground(.fill.tertiary, for: .widget)
                    .widgetURL(entry.url("statistics"))
            }
            .configurationDisplayName(Text("Weekly stats", comment: "Widget name"))
            .description(
                Text("New followers and interactions this week.", comment: "Widget description")
            )
            .supportedFamilies(SnapshotData.lockScreenCountFamilies)
        }
    }

    struct WeeklyStatsView: View {
        @Environment(\.widgetFamily) private var family
        let entry: SnapshotEntry

        private var stats: WidgetSnapshot.Stats? { entry.snapshot?.stats }
        private var change: Int? {
            stats?.followerChange(today: SnapshotData.today(entry.date))?.change
        }

        var body: some View {
            switch family {
            case .accessoryInline:
                Label {
                    if let change {
                        Text(
                            "\(change, format: .number.sign(strategy: .always())) followers this week",
                            comment: "Widget text")
                    } else if let stats {
                        Text(
                            "^[\(stats.followers) follower](inflect: true)", comment: "Widget text")
                    } else {
                        Text("Open Aloha Social", comment: "Widget text, no data yet")
                    }
                } icon: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                }
            case .accessoryCircular:
                circular
            default:
                VStack(alignment: .leading, spacing: 0) {
                    Label {
                        Text("This week", comment: "Lock Screen widget heading")
                    } icon: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                    .font(.headline)
                    .widgetAccentable()
                    if let stats {
                        if let change {
                            Text(
                                "\(change, format: .number.sign(strategy: .always())) followers",
                                comment: "Weekly stats widget")
                        } else {
                            Text(
                                "^[\(stats.followers) follower](inflect: true)",
                                comment: "Widget text")
                        }
                        if let thisWeek = stats.engagementThisWeek {
                            interactions(thisWeek, lastWeek: stats.engagementLastWeek)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        SnapshotPlaceholder.openApp
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.body.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        /// A gauge of this week's interactions against last week's where the
        /// server counts them; otherwise the week's follower change.
        @ViewBuilder
        private var circular: some View {
            if let thisWeek = stats?.engagementThisWeek {
                let lastWeek = max(stats?.engagementLastWeek ?? 0, 1)
                Gauge(value: Double(min(thisWeek, lastWeek * 2)), in: 0...Double(lastWeek * 2)) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                } currentValueLabel: {
                    Text(thisWeek, format: .number.notation(.compactName))
                }
                .gaugeStyle(.accessoryCircular)
                .accessibilityLabel(
                    Text(
                        "^[\(thisWeek) interaction](inflect: true) this week",
                        comment: "Widget text"))
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .widgetAccentable()
                        if let change {
                            Text(change, format: .number.sign(strategy: .always()))
                                .font(.headline.monospacedDigit())
                        } else {
                            Text(stats?.followers ?? 0, format: .number.notation(.compactName))
                                .font(.headline.monospacedDigit())
                        }
                    }
                }
            }
        }

        private func interactions(_ thisWeek: Int, lastWeek: Int?) -> Text {
            guard let lastWeek, lastWeek > 0 else {
                return Text("^[\(thisWeek) interaction](inflect: true)", comment: "Widget text")
            }
            let ratio = Double(thisWeek - lastWeek) / Double(lastWeek)
            return Text(
                "^[\(thisWeek) interaction](inflect: true) · \(ratio, format: .percent.precision(.fractionLength(0)).sign(strategy: .always()))",
                comment: "Weekly stats widget: interactions this week and the change from last week"
            )
        }
    }

#endif

// MARK: - Open messages control

/// "Messages" in Control Center, on the Lock Screen and on the Action button.
struct OpenMessagesControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "social.aloha.app.control.messages") {
            ControlWidgetButton(action: ControlLink.intent("conversations")) {
                Label {
                    Text("Messages", comment: "Control Center control")
                } icon: {
                    Image(systemName: AlohaSymbol.directMessage)
                }
            }
        }
        .displayName(LocalizedStringResource("Messages", comment: "Control Center control"))
        .description(
            LocalizedStringResource(
                "Open your direct messages.", comment: "Control Center control description"))
    }
}
