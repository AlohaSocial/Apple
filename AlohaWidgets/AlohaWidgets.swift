// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaStore
import AppIntents
import CoreGraphics
import SwiftUI
import WidgetKit

/// Timelines are built from the SwiftData store in the app group — a widget
/// never downloads (docs/09 §8).
struct LatestPostsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PostsEntry {
        PostsEntry(
            date: Date(), posts: [], accountHandle: "@you", serverTheme: nil, empty: .nothingYet)
    }

    func snapshot(for configuration: WidgetAccount, in context: Context) async -> PostsEntry {
        await entry(for: configuration, family: context.family)
    }

    func timeline(
        for configuration: WidgetAccount, in context: Context
    ) async -> Timeline<PostsEntry> {
        let entry = await entry(for: configuration, family: context.family)
        // Reloaded by the app after a background refresh and after any post;
        // this interval is only the floor.
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900)))
    }

    private func entry(for configuration: WidgetAccount, family: WidgetFamily) async -> PostsEntry {
        guard let snapshot = await WidgetData.account(matching: configuration) else {
            return PostsEntry(
                date: Date(), posts: [], accountHandle: "", serverTheme: nil, empty: .nothingYet)
        }
        let theme = WidgetData.serverTheme(of: snapshot)
        // A list picked while another account was chosen belongs to that
        // account: its id means nothing, or something else, on this one.
        let listID = configuration.list.flatMap { $0.accountID == snapshot.id ? $0.listID : nil }
        guard let key = configuration.feed.timelineKey(listID: listID) else {
            return PostsEntry(
                date: Date(), posts: [], accountHandle: snapshot.qualifiedHandle,
                serverTheme: theme, empty: .chooseList)
        }
        let posts = await WidgetData.latestPosts(
            accountID: snapshot.id, timelineKey: key,
            limit: LatestPostsView.visibleCount(for: family),
            images: LatestPostsView.imageSizes(for: family))
        return PostsEntry(
            date: Date(), posts: posts, accountHandle: snapshot.qualifiedHandle,
            serverTheme: theme,
            // Home is cached from the first launch; any other feed only once
            // the app has opened it, which is worth saying.
            empty: configuration.feed == .home ? .nothingYet : .openFeedInApp)
    }
}

struct PostsEntry: WidgetKit.TimelineEntry {
    /// Why a widget with no rows has none.
    enum Empty {
        case nothingYet, chooseList, openFeedInApp
    }

    let date: Date
    let posts: [WidgetPost]
    let accountHandle: String
    /// The account's server colour, so the widget wears what the app does.
    let serverTheme: AlohaThemeModifier.ServerTheme?
    let empty: Empty
}

struct WidgetPost: Identifiable {
    let id: String
    /// The local account the post was read with: its link and its heart act
    /// under that account, whichever one the app has active.
    let accountID: UUID
    let author: String
    let handle: String
    let text: String
    let createdAt: Date
    let favourited: Bool
    /// From the app's disk cache, already shrunk; nil where it is not there.
    let avatar: CGImage?
    let thumbnail: CGImage?

    var linkURL: URL? { WidgetData.statusURL(accountID: accountID, statusID: id) }
}

/// A mention, as a widget row: who said it, what they said, and the post it
/// points at so a tap opens the thread rather than the notifications screen.
struct WidgetMention: Identifiable {
    let id: String
    let accountID: UUID
    let author: String
    let handle: String
    let text: String
    let createdAt: Date
    let statusID: String?
    let favourited: Bool
    let avatar: CGImage?

    /// A row without a status has nowhere to open — a mention whose post has
    /// since been deleted is still worth reading, but the link cannot point at
    /// nothing.
    var linkURL: URL? {
        statusID.flatMap { WidgetData.statusURL(accountID: accountID, statusID: $0) }
    }
}

/// An author's picture on a row, or their initial where the app has not
/// cached the picture: the widget never fetches one itself.
struct WidgetAvatar: View {
    let image: CGImage?
    let name: String
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .widgetAccentedRenderingMode(.accentedDesaturated)
                    .scaledToFill()
            } else {
                Circle()
                    .fill(.tint.opacity(0.2))
                    .overlay {
                        Text(verbatim: String(name.prefix(1)).uppercased())
                            .font(.system(size: size * 0.5, weight: .semibold))
                            .foregroundStyle(.tint)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// The heart on a row: favourites the post from the widget itself, without
/// opening the app (`FavouriteFromWidgetIntent`).
struct FavouriteButton: View {
    @Environment(\.alohaPalette) private var palette

    let accountID: UUID
    let statusID: String
    let favourited: Bool

    var body: some View {
        Button(
            intent: FavouriteFromWidgetIntent(
                accountID: accountID, statusID: statusID, favourite: !favourited)
        ) {
            // The app's own heart and amber, with the fill as the shape
            // change that does not rely on colour (docs/12 §3).
            Image(systemName: favourited ? AlohaSymbol.favouriteFilled : AlohaSymbol.favourite)
                .font(.caption)
                // Hierarchical grey rather than a palette role: the widget's
                // environment carries the default light palette even on a
                // dark Home Screen.
                .foregroundStyle(
                    favourited ? AnyShapeStyle(palette.favourite) : AnyShapeStyle(.secondary)
                )
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            favourited
                ? Text("Unfavourite", comment: "Widget button")
                : Text("Favourite", comment: "Widget button"))
    }
}

struct LatestPostsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "LatestPosts", intent: WidgetAccount.self, provider: LatestPostsProvider()
        ) { entry in
            LatestPostsView(entry: entry)
                .serverTint(entry.serverTheme)
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

    static func visibleCount(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 2
        case .systemLarge: 5
        case .systemExtraLarge: 12
        default: 3
        }
    }

    /// Avatars at every size; a post's picture only where a row has room
    /// beside the text for it to be more than a smudge.
    static func imageSizes(for family: WidgetFamily) -> WidgetImages.Sizes {
        switch family {
        case .systemSmall, .systemMedium: WidgetImages.Sizes(avatar: 64, thumbnail: nil)
        case .systemLarge, .systemExtraLarge: WidgetImages.Sizes(avatar: 64, thumbnail: 160)
        default: .none
        }
    }

    /// An extra-large widget is wide enough for two columns, which is what
    /// makes reading it at that size possible at all.
    private var columns: Int {
        family == .systemExtraLarge ? 2 : 1
    }

    var body: some View {
        let rows = Array(entry.posts.prefix(Self.visibleCount(for: family)))
        Grid(horizontalSpacing: 8, verticalSpacing: 6) {
            if rows.isEmpty {
                GridRow {
                    emptyText
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

    private var emptyText: Text {
        switch entry.empty {
        case .nothingYet:
            Text("Nothing yet", comment: "Empty widget")
        case .chooseList:
            Text(
                "Choose a list in the widget's settings.",
                comment: "Latest posts widget set to a list without one picked")
        case .openFeedInApp:
            Text(
                "Open this feed in Aloha Social to show it here.",
                comment: "Latest posts widget whose feed the app has not cached")
        }
    }

    private func postRow(_ post: WidgetPost) -> some View {
        HStack(alignment: .top, spacing: 4) {
            if let url = post.linkURL {
                Link(destination: url) { postContent(post) }
            } else {
                postContent(post)
            }
            FavouriteButton(
                accountID: post.accountID, statusID: post.id, favourited: post.favourited)
        }
    }

    private func postContent(_ post: WidgetPost) -> some View {
        HStack(alignment: .top, spacing: 6) {
            WidgetAvatar(image: post.avatar, name: post.author)
            postText(post)
            if let thumbnail = post.thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .widgetAccentedRenderingMode(.accentedDesaturated)
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    private func postText(_ post: WidgetPost) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(post.author)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                    .widgetAccentable()
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

// MARK: - Notifications widget

struct UnreadProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UnreadEntry {
        UnreadEntry(date: Date(), count: 0, accountHandle: nil, serverTheme: nil)
    }

    func snapshot(
        for configuration: NotificationsWidgetAccount, in context: Context
    ) async -> UnreadEntry {
        await entry(for: configuration)
    }

    func timeline(
        for configuration: NotificationsWidgetAccount, in context: Context
    ) async -> Timeline<UnreadEntry> {
        Timeline(
            entries: [await entry(for: configuration)],
            policy: .after(Date().addingTimeInterval(900)))
    }

    /// Set to an account, that account's count and colour; unset, every
    /// account's total in the active account's colour, as before the widget
    /// could be configured.
    private func entry(for configuration: NotificationsWidgetAccount) async -> UnreadEntry {
        let picked = configuration.account?.id
        let snapshot = await WidgetData.account(id: picked)
        return UnreadEntry(
            date: Date(), count: WidgetData.unreadCount(accountID: picked),
            accountHandle: picked == nil ? nil : snapshot?.qualifiedHandle,
            serverTheme: snapshot.flatMap(WidgetData.serverTheme(of:)))
    }
}

struct UnreadEntry: WidgetKit.TimelineEntry {
    let date: Date
    let count: Int
    /// Shown where there is room, when the widget is set to one account.
    let accountHandle: String?
    let serverTheme: AlohaThemeModifier.ServerTheme?
}

struct UnreadWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "Unread", intent: NotificationsWidgetAccount.self, provider: UnreadProvider()
        ) { entry in
            UnreadView(entry: entry)
                .serverTint(entry.serverTheme)
                .containerBackground(.fill.tertiary, for: .widget)
                // A count is a door to the list it counts.
                .widgetURL(URL(string: "alohasocial://notifications"))
        }
        .configurationDisplayName(Text("Unread notifications", comment: "Widget name"))
        .description(Text("How many things happened.", comment: "Widget description"))
        .supportedFamilies(Self.families)
    }

    /// The Lock Screen and StandBy families are the iPhone's; a Mac has
    /// none of them.
    private static var families: [WidgetFamily] {
        #if os(iOS)
            [.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
            [.systemSmall]
        #endif
    }
}

struct UnreadView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UnreadEntry

    var body: some View {
        switch family {
        #if os(iOS)
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
            case .accessoryRectangular:
                // Three short lines, the Lock Screen's own shape for a count:
                // what it is, how many, and whose.
                VStack(alignment: .leading, spacing: 0) {
                    Label {
                        Text("Notifications", comment: "Lock Screen widget heading")
                    } icon: {
                        Image(systemName: "bell.fill")
                    }
                    .font(.headline)
                    .widgetAccentable()
                    Text("\(entry.count) unread", comment: "Lock Screen widget count")
                        .font(.body.monospacedDigit())
                        .contentTransition(.numericText())
                    if let handle = entry.accountHandle {
                        Text(handle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        #endif
        default:
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "bell.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .widgetAccentable()
                Text(entry.count, format: .number)
                    .font(.largeTitle.weight(.bold))
                    .contentTransition(.numericText())
                Text("unread", comment: "Widget label")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let handle = entry.accountHandle {
                    Text(handle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
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
        MemoriesWidget()
        QuickComposeWidget()
        NewPostControl()
        NewStoryControl()
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
        MentionsEntry(date: Date(), mentions: [], accountHandle: "@you", serverTheme: nil)
    }

    func snapshot(
        for configuration: NotificationsWidgetAccount, in context: Context
    ) async -> MentionsEntry {
        await entry(for: configuration)
    }

    func timeline(
        for configuration: NotificationsWidgetAccount, in context: Context
    ) async -> Timeline<MentionsEntry> {
        Timeline(
            entries: [await entry(for: configuration)],
            policy: .after(Date().addingTimeInterval(600)))
    }

    private func entry(for configuration: NotificationsWidgetAccount) async -> MentionsEntry {
        guard let snapshot = await WidgetData.account(id: configuration.account?.id) else {
            return MentionsEntry(date: Date(), mentions: [], accountHandle: "", serverTheme: nil)
        }
        let mentions = await WidgetData.latestMentions(
            accountID: snapshot.id, limit: 6, avatarPixels: 64)
        return MentionsEntry(
            date: Date(), mentions: mentions, accountHandle: snapshot.qualifiedHandle,
            serverTheme: WidgetData.serverTheme(of: snapshot))
    }
}

struct MentionsEntry: WidgetKit.TimelineEntry {
    let date: Date
    let mentions: [WidgetMention]
    let accountHandle: String
    /// The account's server colour, so the widget wears what the app does.
    let serverTheme: AlohaThemeModifier.ServerTheme?
}

struct MentionsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "Mentions", intent: NotificationsWidgetAccount.self,
            provider: MentionsProvider()
        ) { entry in
            MentionsView(entry: entry)
                .serverTint(entry.serverTheme)
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
                    HStack(alignment: .top, spacing: 2) {
                        if let url = mention.linkURL {
                            Link(destination: url) { row(mention) }
                        } else {
                            row(mention)
                        }
                        if let statusID = mention.statusID {
                            FavouriteButton(
                                accountID: mention.accountID, statusID: statusID,
                                favourited: mention.favourited)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func row(_ mention: WidgetMention) -> some View {
        HStack(alignment: .top, spacing: 6) {
            WidgetAvatar(image: mention.avatar, name: mention.author)
            rowText(mention)
        }
    }

    private func rowText(_ mention: WidgetMention) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(mention.author)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                    .widgetAccentable()
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

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date()))
    }

    /// Nothing to show: the widget is a button, so its content never changes
    /// and the entry is stamped once.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(
            Timeline(
                entries: [SimpleEntry(date: Date())],
                policy: .after(Date().addingTimeInterval(3600))))
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

// MARK: - Control Center

/// The app's own links, as the system intent that opens them.
///
/// `OpenURLIntent` hands the link to the app through the same `onOpenURL` a
/// tapped widget uses, so a control runs nothing in this extension and needs
/// no account, store or network — none of which an extension can reach while
/// the app group is off.
enum ControlLink {
    static func intent(_ host: String) -> OpenURLIntent {
        var components = URLComponents()
        components.scheme = "alohasocial"
        components.host = host
        // A scheme and a bare host always make a URL; the fallback is never
        // reached and opens nothing rather than crashing.
        return OpenURLIntent(components.url ?? URL(filePath: "/"))
    }
}

/// "New post" in Control Center, on the Lock Screen and on the Action button.
struct NewPostControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "social.aloha.app.control.newPost") {
            ControlWidgetButton(action: ControlLink.intent("compose")) {
                Label {
                    Text("New post", comment: "Control Center control")
                } icon: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .displayName(LocalizedStringResource("New post", comment: "Control Center control"))
        .description(
            LocalizedStringResource(
                "Open the composer.", comment: "Control Center control description"))
    }
}

/// "New story": the story composer, on servers that have stories.
struct NewStoryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "social.aloha.app.control.newStory") {
            ControlWidgetButton(action: ControlLink.intent("story")) {
                Label {
                    Text("New story", comment: "Control Center control")
                } icon: {
                    Image(systemName: "camera.circle")
                }
            }
        }
        .displayName(LocalizedStringResource("New story", comment: "Control Center control"))
        .description(
            LocalizedStringResource(
                "Open the story composer.", comment: "Control Center control description"))
    }
}
