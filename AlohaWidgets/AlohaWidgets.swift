// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaStore
import AppIntents
import SwiftUI
import WidgetKit

/// Timelines are built from the SwiftData store in the app group — a widget
/// never downloads (docs/09 §8).
struct LatestPostsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PostsEntry {
        PostsEntry(date: Date(), posts: [], accountHandle: "@you")
    }

    func snapshot(for configuration: WidgetAccount, in context: Context) async -> PostsEntry {
        await entry(for: configuration)
    }

    func timeline(
        for configuration: WidgetAccount, in context: Context
    ) async -> Timeline<PostsEntry> {
        let entry = await entry(for: configuration)
        // Reloaded by the app after a background refresh and after any post;
        // this interval is only the floor.
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900)))
    }

    private func entry(for configuration: WidgetAccount) async -> PostsEntry {
        guard let snapshot = await WidgetData.account(matching: configuration) else {
            return PostsEntry(date: Date(), posts: [], accountHandle: "")
        }
        let posts = await WidgetData.latestPosts(accountID: snapshot.id, limit: 6)
        return PostsEntry(date: Date(), posts: posts, accountHandle: snapshot.qualifiedHandle)
    }
}

struct PostsEntry: WidgetKit.TimelineEntry {
    let date: Date
    let posts: [WidgetPost]
    let accountHandle: String
}

struct WidgetPost: Identifiable, Hashable {
    let id: String
    let author: String
    let handle: String
    let text: String
    let createdAt: Date
}

/// A mention, as a widget row: who said it, what they said, and the post it
/// points at so a tap opens the thread rather than the notifications screen.
struct WidgetMention: Identifiable, Hashable {
    let id: String
    let author: String
    let handle: String
    let text: String
    let createdAt: Date
    let statusID: String?

    /// A row without a status has nowhere to open — a mention whose post has
    /// since been deleted is still worth reading, but the link cannot point at
    /// nothing.
    var linkURL: URL? {
        guard let statusID else { return nil }
        return URL(string: "alohasocial://status/0/\(statusID)")
    }
}

struct WidgetAccount: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Account"
    static let description = IntentDescription("Which account to show.")

    @Parameter(title: "Handle")
    var handle: String?

    init() {}
}

struct LatestPostsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "LatestPosts", intent: WidgetAccount.self, provider: LatestPostsProvider()
        ) { entry in
            LatestPostsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("Latest posts", comment: "Widget name"))
        .description(Text("Recent posts from your home timeline.", comment: "Widget description"))
        // systemExtraLarge is the iPad and Mac family (docs/09 §8): a widget
        // the size of a window, which is the one place a timeline earns it.
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
        ])
    }
}

struct LatestPostsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PostsEntry

    private var visibleCount: Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 2
        case .systemLarge: 5
        case .systemExtraLarge: 12
        default: 3
        }
    }

    /// An extra-large widget is wide enough for two columns, which is what
    /// makes reading it at that size possible at all.
    private var columns: Int {
        family == .systemExtraLarge ? 2 : 1
    }

    var body: some View {
        let rows = Array(entry.posts.prefix(visibleCount))
        Grid(horizontalSpacing: 8, verticalSpacing: 6) {
            if rows.isEmpty {
                GridRow {
                    Text("Nothing yet", comment: "Empty widget")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .gridCellColumns(columns)
                }
            } else {
                let columnCount = (rows.count + columns - 1) / columns
                ForEach(0..<columnCount, id: \.self) { row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index < rows.count {
                                postRow(rows[index])
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func postRow(_ post: WidgetPost) -> some View {
        Link(destination: URL(string: "alohasocial://status/0/\(post.id)")!) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(post.author)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(
                        post.createdAt,
                        format: .relative(presentation: .numeric, unitsStyle: .narrow)
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                Text(post.text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(family == .systemSmall ? 4 : 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Notifications widget

struct UnreadProvider: TimelineProvider {
    func placeholder(in context: Context) -> UnreadEntry {
        UnreadEntry(date: Date(), count: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (UnreadEntry) -> Void) {
        Task { completion(await entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UnreadEntry>) -> Void) {
        Task {
            completion(
                Timeline(
                    entries: [await entry()],
                    policy: .after(Date().addingTimeInterval(900))))
        }
    }

    private func entry() async -> UnreadEntry {
        UnreadEntry(date: Date(), count: await WidgetData.unreadCount())
    }
}

struct UnreadEntry: WidgetKit.TimelineEntry {
    let date: Date
    let count: Int
}

struct UnreadWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Unread", provider: UnreadProvider()) { entry in
            UnreadView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("Unread notifications", comment: "Widget name"))
        .description(Text("How many things happened.", comment: "Widget description"))
        .supportedFamilies([
            .systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct UnreadView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UnreadEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Label {
                Text("^[\(entry.count) notification](inflect: true)", comment: "Widget text")
            } icon: {
                Image(systemName: "bell.fill")
            }
        case .accessoryCircular:
            Gauge(value: Double(min(entry.count, 99)), in: 0...99) {
                Image(systemName: "bell.fill")
            } currentValueLabel: {
                Text(entry.count, format: .number)
            }
            .gaugeStyle(.accessoryCircular)
        default:
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "bell.fill").font(.title3)
                Text(entry.count, format: .number)
                    .font(.largeTitle.weight(.bold))
                    .contentTransition(.numericText())
                Text("unread", comment: "Widget label")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@main
struct AlohaWidgetBundle: WidgetBundle {
    var body: some Widget {
        LatestPostsWidget()
        UnreadWidget()
        MentionsWidget()
        QuickComposeWidget()
        #if os(iOS)
            UploadLiveActivity()
        #endif
    }
}

// MARK: - Mentions widget

/// The newest mentions, as rows rather than a count (docs/09 §8).
///
/// Mentions are the one kind that never group, so a row is a row — and a
/// mention is what somebody opens their phone for.
struct MentionsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MentionsEntry {
        MentionsEntry(date: Date(), mentions: [], accountHandle: "@you")
    }

    func snapshot(for configuration: WidgetAccount, in context: Context) async -> MentionsEntry {
        await entry(for: configuration)
    }

    func timeline(
        for configuration: WidgetAccount, in context: Context
    ) async -> Timeline<MentionsEntry> {
        Timeline(
            entries: [await entry(for: configuration)],
            policy: .after(Date().addingTimeInterval(600)))
    }

    private func entry(for configuration: WidgetAccount) async -> MentionsEntry {
        guard let snapshot = await WidgetData.account(matching: configuration) else {
            return MentionsEntry(date: Date(), mentions: [], accountHandle: "")
        }
        let mentions = await WidgetData.latestMentions(accountID: snapshot.id, limit: 6)
        return MentionsEntry(
            date: Date(), mentions: mentions, accountHandle: snapshot.qualifiedHandle)
    }
}

struct MentionsEntry: WidgetKit.TimelineEntry {
    let date: Date
    let mentions: [WidgetMention]
    let accountHandle: String
}

struct MentionsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "Mentions", intent: WidgetAccount.self, provider: MentionsProvider()
        ) { entry in
            MentionsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("Mentions", comment: "Widget name"))
        .description(Text("The newest things said to you.", comment: "Widget description"))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct MentionsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MentionsEntry

    private var visibleCount: Int { family == .systemLarge ? 6 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.mentions.isEmpty {
                Text("Nothing said lately", comment: "Empty mentions widget")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.mentions.prefix(visibleCount)) { mention in
                    Group {
                        if let url = mention.linkURL {
                            Link(destination: url) { row(mention) }
                        } else {
                            row(mention)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func row(_ mention: WidgetMention) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(mention.author)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(
                    mention.createdAt,
                    format: .relative(presentation: .numeric, unitsStyle: .narrow)
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Text(mention.text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Quick compose widget

/// A button, not a timeline: it deep-links straight into the composer
/// (docs/09 §8).
struct QuickComposeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickCompose", provider: QuickComposeProvider()) { _ in
            QuickComposeView()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("Quick compose", comment: "Widget name"))
        .description(Text("Open the composer.", comment: "Widget description"))
        .supportedFamilies([.systemSmall])
    }
}

struct QuickComposeProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func snapshot(in context: Context) async -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    /// Nothing to show: the widget is a button, so its content never changes
    /// and the entry is stamped once.
    func timeline(in context: Context) async -> Timeline<SimpleEntry> {
        Timeline(
            entries: [SimpleEntry(date: Date())], policy: .after(Date().addingTimeInterval(3600)))
    }
}

struct SimpleEntry: WidgetKit.TimelineEntry {
    let date: Date
}

struct QuickComposeView: View {
    var body: some View {
        Link(destination: URL(string: "alohasocial://compose")!) {
            VStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
                Text("New post", comment: "Quick compose widget")
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
