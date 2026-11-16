// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaStore
import Charts
import SwiftUI
import WidgetKit

// MARK: - Conversations

/// The newest direct-message threads: who, the last line, and whether it is
/// unread. A tap opens the thread.
struct ConversationsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SnapshotWidgetKind.conversations.kind, intent: NotificationsWidgetAccount.self,
            provider: SnapshotProvider(kind: .conversations)
        ) { entry in
            ConversationsView(entry: entry)
                .serverTint(entry.serverTheme)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.url("conversations"))
        }
        .configurationDisplayName(Text("Conversations", comment: "Widget name"))
        .description(Text("Your latest direct messages.", comment: "Widget description"))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ConversationsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var visibleCount: Int { family == .systemLarge ? 6 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeading(
                symbol: AlohaSymbol.directMessageFilled,
                title: Text("Messages", comment: "Widget heading"),
                trailing: unreadLabel)
            if let messages = entry.snapshot?.messages {
                if messages.conversations.isEmpty {
                    Text("No messages yet", comment: "Empty conversations widget")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(messages.conversations.prefix(visibleCount)) { row in
                        if let url = entry.statusURL(row.lastStatusID) {
                            Link(destination: url) { conversationRow(row) }
                        } else {
                            conversationRow(row)
                        }
                    }
                }
            } else {
                SnapshotPlaceholder.openApp
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var unreadLabel: Text? {
        guard let unread = entry.snapshot?.messages?.unread, unread > 0 else { return nil }
        return Text("\(unread) unread", comment: "Lock Screen widget count")
    }

    private func conversationRow(_ row: WidgetSnapshot.ConversationRow) -> some View {
        HStack(alignment: .top, spacing: 6) {
            WidgetAvatar(image: entry.image(row.avatarFile), name: row.names, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(row.names)
                        .font(.caption.weight(row.unread ? .bold : .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(row.date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if row.unread {
                        Circle()
                            .fill(.tint)
                            .frame(width: 7, height: 7)
                            .widgetAccentable()
                            .accessibilityLabel(Text("Unread", comment: "Widget row state"))
                    }
                }
                Text(row.text)
                    .font(.caption2)
                    .foregroundStyle(row.unread ? .primary : .secondary)
                    .lineLimit(1)
                    .privacySensitive()
            }
        }
    }
}

// MARK: - Live poll

/// Your newest poll: live bars while it runs, the result for a day after.
struct LivePollWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SnapshotWidgetKind.poll.kind, intent: NotificationsWidgetAccount.self,
            provider: SnapshotProvider(kind: .poll)
        ) { entry in
            LivePollView(entry: entry)
                .serverTint(entry.serverTheme)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.statusURL(entry.snapshot?.poll?.statusID))
        }
        .configurationDisplayName(Text("Live poll", comment: "Widget name"))
        .description(
            Text("How your latest poll is going.", comment: "Widget description")
        )
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct LivePollView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let poll = entry.snapshot?.poll {
                WidgetHeading(
                    symbol: AlohaSymbol.poll, title: Text("Your poll", comment: "Widget heading"),
                    trailing: status(poll))
                Text(poll.question)
                    .font(.caption.weight(.semibold))
                    .lineLimit(family == .systemLarge ? 3 : 1)
                ForEach(Array(poll.options.prefix(4).enumerated()), id: \.offset) { _, option in
                    optionBar(option, poll: poll)
                }
                Spacer(minLength: 0)
                Text("^[\(poll.voters) person](inflect: true) voted", comment: "Poll widget")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if entry.snapshot == nil {
                SnapshotPlaceholder(symbol: AlohaSymbol.poll, text: SnapshotPlaceholder.openApp)
            } else {
                SnapshotPlaceholder(
                    symbol: AlohaSymbol.poll,
                    text: Text(
                        "No poll running. Your next one shows up here.",
                        comment: "Empty poll widget"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func status(_ poll: WidgetSnapshot.Poll) -> Text {
        if poll.isClosed(at: entry.date) {
            return Text("Final results", comment: "Poll widget, closed")
        }
        guard let closes = poll.expiresAt else {
            return Text("Open", comment: "Poll widget, no end date")
        }
        return Text("Ends \(Text(closes, style: .relative))", comment: "Poll widget, time left")
    }

    private func optionBar(
        _ option: WidgetSnapshot.Poll.Option, poll: WidgetSnapshot.Poll
    )
        -> some View
    {
        let total = max(poll.totalVotes, 1)
        let share = Double(option.votes) / Double(total)
        let leading = poll.options.map(\.votes).max() == option.votes && option.votes > 0
        return ZStack(alignment: .leading) {
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.tint.opacity(leading ? 0.45 : 0.2))
                    .frame(width: max(proxy.size.width * share, 4))
                    .widgetAccentable()
            }
            HStack {
                Text(option.title)
                    .font(.caption2.weight(leading ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(share, format: .percent.precision(.fractionLength(0)))
                    .font(.caption2.monospacedDigit())
            }
            .padding(.horizontal, 6)
        }
        .frame(height: family == .systemLarge ? 26 : 18)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Creator dashboard

/// The week in numbers — followers with their line, interactions, posts —
/// with what is waiting to go out underneath. In December, the year.
struct CreatorDashboardWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SnapshotWidgetKind.dashboard.kind, intent: NotificationsWidgetAccount.self,
            provider: SnapshotProvider(kind: .dashboard)
        ) { entry in
            CreatorDashboardView(entry: entry)
                .serverTint(entry.serverTheme)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.url("statistics"))
        }
        .configurationDisplayName(Text("Creator dashboard", comment: "Widget name"))
        .description(
            Text(
                "Your week in numbers, with scheduled posts and drafts.",
                comment: "Widget description")
        )
        .supportedFamilies([.systemMedium])
    }
}

struct CreatorDashboardView: View {
    let entry: SnapshotEntry

    private var stats: WidgetSnapshot.Stats? { entry.snapshot?.stats }
    private var next: WidgetSnapshot.ScheduledPost? {
        entry.snapshot?.scheduled?.first { $0.at > entry.date }
    }

    /// The annual report is ready through December.
    private var isYearInReview: Bool {
        Calendar.current.component(.month, from: entry.date) == 12
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeading(
                symbol: "chart.bar.xaxis",
                title: Text("This week", comment: "Widget heading"),
                trailing: Text(entry.accountHandle))
            if let stats {
                HStack(alignment: .bottom, spacing: 10) {
                    tile(
                        value: Text(stats.followers, format: .number.notation(.compactName)),
                        label: followerLabel(stats))
                    if let thisWeek = stats.engagementThisWeek {
                        tile(
                            value: Text(thisWeek, format: .number.notation(.compactName)),
                            label: Text("interactions", comment: "Dashboard tile"))
                    }
                    if let posts = stats.postsThisWeek {
                        tile(
                            value: Text(posts, format: .number),
                            label: Text("posts", comment: "Dashboard tile"))
                    }
                    sparkline(stats)
                }
            } else {
                SnapshotPlaceholder.openApp
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func followerLabel(_ stats: WidgetSnapshot.Stats) -> Text {
        guard let change = stats.followerChange(today: SnapshotData.today(entry.date))?.change
        else { return Text("followers", comment: "Dashboard tile") }
        return Text(
            "followers \(change, format: .number.sign(strategy: .always()))",
            comment: "Dashboard tile: followers and the week's change")
    }

    private func tile(value: Text, label: Text) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            value
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            label
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// The follower line over the days the app has looked; nothing until
    /// there are two days to draw between.
    @ViewBuilder
    private func sparkline(_ stats: WidgetSnapshot.Stats) -> some View {
        if stats.history.count >= 2 {
            Chart(Array(stats.history.enumerated()), id: \.offset) { index, sample in
                LineMark(x: .value("Day", index), y: .value("Followers", sample.followers))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.tint)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(maxWidth: .infinity, maxHeight: 36)
            .widgetAccentable()
            .accessibilityHidden(true)
        } else {
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if isYearInReview, let url = entry.url("year") {
                Link(destination: url) {
                    Label {
                        Text("Your year in review is ready", comment: "Dashboard footer")
                    } icon: {
                        Image(systemName: AlohaSymbol.sparkles)
                    }
                    .foregroundStyle(.tint)
                }
            } else if let next, let url = entry.url("scheduled") {
                Link(destination: url) {
                    Label {
                        Text(
                            "Next post \(Text(next.at, style: .relative))",
                            comment: "Dashboard footer: time until the next scheduled post")
                    } icon: {
                        Image(systemName: "clock")
                    }
                }
            }
            Spacer(minLength: 0)
            if entry.drafts > 0, let url = entry.url("drafts") {
                Link(destination: url) {
                    Label {
                        Text("^[\(entry.drafts) draft](inflect: true)", comment: "Dashboard footer")
                    } icon: {
                        Image(systemName: AlohaSymbol.edit)
                    }
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

// MARK: - What's happening

/// What the account's server is talking about: trending hashtags and links.
struct ServerTrendsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SnapshotWidgetKind.trends.kind, intent: NotificationsWidgetAccount.self,
            provider: SnapshotProvider(kind: .trends)
        ) { entry in
            ServerTrendsView(entry: entry)
                .serverTint(entry.serverTheme)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.url("explore"))
        }
        .configurationDisplayName(Text("What's happening", comment: "Widget name"))
        .description(
            Text(
                "Trending hashtags and links on your server.", comment: "Widget description")
        )
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ServerTrendsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var host: String {
        entry.accountHandle.split(separator: "@").last.map(String.init) ?? entry.accountHandle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeading(
                symbol: "flame",
                title: Text("On \(host)", comment: "Trends widget heading: the server's name"))
            if let trends = entry.snapshot?.trends, !(trends.tags.isEmpty && trends.links.isEmpty) {
                tags(trends.tags)
                ForEach(trends.links.prefix(family == .systemLarge ? 4 : 2)) { link in
                    Link(destination: link.url) { linkRow(link) }
                }
            } else if entry.snapshot?.trends == nil {
                SnapshotPlaceholder.openApp
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Nothing trending right now", comment: "Empty trends widget")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func tags(_ tags: [WidgetSnapshot.Trends.Tag]) -> some View {
        ViewThatFits(in: .horizontal) {
            ForEach([4, 3, 2, 1], id: \.self) { count in
                HStack(spacing: 4) {
                    ForEach(tags.prefix(count)) { tag in tagChip(tag) }
                }
            }
        }
    }

    @ViewBuilder
    private func tagChip(_ tag: WidgetSnapshot.Trends.Tag) -> some View {
        let chip = VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "#\(tag.name)")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
            if family == .systemLarge {
                Text("^[\(tag.uses) post](inflect: true)", comment: "Trends widget")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.tint.opacity(0.15), in: Capsule())
        if let url = URL(string: "alohasocial://tag/\(tag.name)") {
            Link(destination: url) { chip }
        } else {
            chip
        }
    }

    private func linkRow(_ link: WidgetSnapshot.Trends.Link) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if let image = entry.image(link.imageFile) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .widgetAccentedRenderingMode(.accentedDesaturated)
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(link.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
                if let provider = link.provider, !provider.isEmpty {
                    Text(provider)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
