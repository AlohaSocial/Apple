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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct LatestPostsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PostsEntry

    private var visibleCount: Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 2
        default: 5
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.posts.isEmpty {
                Text("Nothing yet", comment: "Empty widget")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.posts.prefix(visibleCount)) { post in
                    Link(destination: URL(string: "alohasocial://status/0/\(post.id)")!) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(post.author)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(
                                    post.createdAt,
                                    format: .relative(
                                        presentation: .numeric, unitsStyle: .narrow)
                                )
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }
                            Text(post.text)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(family == .systemSmall ? 4 : 2)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
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
        #if os(iOS)
            UploadLiveActivity()
        #endif
    }
}
