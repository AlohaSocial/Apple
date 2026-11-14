// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI
import WatchConnectivity

/// A companion, not a client. It never authenticates on its own: the phone
/// hands it the active account's token and API base on pairing and on change,
/// and it keeps that in the watch's own Keychain with the same accessibility
/// class (docs/09 §4).
@main
struct AlohaSocialWatchApp: App {
    @State private var link = WatchLink()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(link)
        }
    }
}

struct WatchRootView: View {
    @Environment(WatchLink.self) private var link
    @Environment(\.scenePhase) private var scenePhase
    /// Where a tapped complication, or a toolbar button, asked to go.
    @State private var path: [WatchDestination] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if link.credentials == nil {
                    ContentUnavailableView {
                        Text("Not paired yet", comment: "Watch, no credentials")
                    } description: {
                        Text(
                            "Open Aloha Social on your iPhone to finish setting this up.",
                            comment: "Watch, no credentials detail")
                    }
                } else {
                    WatchTimelineView()
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                NavigationLink(value: WatchDestination.mentions) {
                                    Image(systemName: "at")
                                }
                                .accessibilityLabel(
                                    Text("Mentions", comment: "Watch mentions screen title"))
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink(value: WatchDestination.notifications) {
                                    Image(systemName: AlohaSymbol.notifications)
                                }
                                .accessibilityLabel(
                                    Text(
                                        "Notifications", comment: "Watch notifications screen title"
                                    ))
                            }
                        }
                }
            }
            .navigationTitle(Text("Aloha", comment: "Watch app title"))
            .navigationDestination(for: WatchDestination.self) { destination in
                switch destination {
                case .mentions: WatchMentionsView()
                case .notifications: WatchNotificationsView()
                case .status(let id): WatchStatusLoader(statusID: id)
                }
            }
        }
        .serverTint(link.serverTheme)
        .task { link.activate() }
        .onOpenURL { url in
            guard let link = WatchComplicationLink(url: url) else { return }
            path = [WatchDestination(link)]
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task { await link.refreshComplications() }
        }
    }
}

/// The screens the watch app pushes: the complications' two, and the
/// notifications list the timeline's toolbar opens.
enum WatchDestination: Hashable {
    case mentions
    case notifications
    case status(String)

    init(_ link: WatchComplicationLink) {
        switch link {
        case .mentions: self = .mentions
        case .status(let id): self = .status(id)
        }
    }
}

/// The newest mentions, which is what the mentions complication opens.
struct WatchMentionsView: View {
    @Environment(WatchLink.self) private var link
    @State private var feed = WatchFeed<MastodonNotification>(.mentions)

    var body: some View {
        List {
            ForEach(feed.items) { mention in
                if let status = mention.status {
                    NavigationLink {
                        WatchStatusView(status: status)
                    } label: {
                        WatchPostRow(status: status, title: mention.account.bestDisplayName)
                    }
                }
            }
            if feed.items.isEmpty && !feed.isLoading && !feed.isShowingCache {
                Text("No mentions yet", comment: "Watch, empty mentions list").font(.caption2)
            }
            if feed.isShowingCache {
                WatchUpdatedHint(updatedAt: feed.updatedAt)
            }
        }
        .navigationTitle(Text("Mentions", comment: "Watch mentions screen title"))
        .task(id: link.credentials?.accountID) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        await feed.load(accountID: link.credentials?.accountID) {
            guard let client = link.client else { throw APIError.invalidResponse }
            let page = try await client.decode(
                LossyArray<MastodonNotification>.self,
                from: Endpoint.notifications.flat(limit: 20, types: ["mention"]))
            // Filtered here as well: a server that ignores `types` answers
            // with every kind.
            return page.elements.filter { $0.type == .mention }
        }
    }
}

/// One post by id: a complication row carries the id, not the post.
struct WatchStatusLoader: View {
    @Environment(WatchLink.self) private var link
    let statusID: String
    @State private var status: Status?
    @State private var failed = false

    var body: some View {
        Group {
            if let status {
                WatchStatusView(status: status)
            } else if failed {
                Text("Couldn't load this post", comment: "Watch, post failed to load")
                    .font(.caption2)
            } else {
                ProgressView()
            }
        }
        .task {
            guard let client = link.client else {
                failed = true
                return
            }
            do {
                status = try await client.decode(
                    Status.self, from: Endpoint.statuses.status(statusID))
            } catch {
                failed = true
            }
        }
    }
}

struct WatchTimelineView: View {
    @Environment(WatchLink.self) private var link
    @State private var feed = WatchFeed<Status>(.timeline)

    var body: some View {
        List {
            ForEach(feed.items) { status in
                NavigationLink {
                    WatchStatusView(status: status)
                } label: {
                    WatchPostRow(status: status)
                }
            }
            if feed.items.isEmpty && !feed.isLoading && !feed.isShowingCache {
                Text("Nothing yet", comment: "Watch empty timeline").font(.caption2)
            }
            if feed.isShowingCache {
                WatchUpdatedHint(updatedAt: feed.updatedAt)
            }
        }
        .task(id: link.credentials?.accountID) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        await feed.load(accountID: link.credentials?.accountID) {
            guard let client = link.client else { throw APIError.invalidResponse }
            // Text and thumbnails only; no video on the wrist.
            return try await client.decode(
                LossyArray<Status>.self,
                from: Endpoint.timelines.timeline(.home, limit: 20)
            ).elements
        }
    }
}

struct WatchStatusView: View {
    @Environment(WatchLink.self) private var link
    let status: Status

    @State private var isFavourited: Bool
    @State private var isBoosted: Bool
    @State private var reply: ReplyState = .idle

    private enum ReplyState: Equatable {
        case idle, sending, sent, failed
    }

    init(status: Status) {
        self.status = status
        _isFavourited = State(initialValue: status.displayed.favourited)
        _isBoosted = State(initialValue: status.displayed.reblogged)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(status.displayed.account.bestDisplayName)
                    .font(.caption.weight(.semibold))
                WatchPostBody(status: status)

                HStack(spacing: 12) {
                    // The app's own heart, not a star: a favourite is the
                    // same act on the wrist as on the phone (`AlohaSymbol`).
                    Button {
                        toggle($isFavourited, on: .favourite, off: .unfavourite)
                    } label: {
                        Image(
                            systemName: isFavourited
                                ? AlohaSymbol.favouriteFilled : AlohaSymbol.favourite
                        )
                        .foregroundStyle(
                            isFavourited ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    }
                    .accessibilityLabel(
                        isFavourited
                            ? Text("Remove favourite", comment: "Watch post action")
                            : Text("Favourite", comment: "Watch post action"))
                    Button {
                        toggle($isBoosted, on: .reblog, off: .unreblog)
                    } label: {
                        Image(systemName: AlohaSymbol.boost)
                            .foregroundStyle(
                                isBoosted ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    }
                    .accessibilityLabel(
                        isBoosted
                            ? Text("Undo boost", comment: "Watch post action")
                            : Text("Boost", comment: "Watch post action"))
                }
                .buttonStyle(.bordered)

                // Dictation, Scribble and emoji come with the system's own
                // text entry; the watch has no keyboard worth building.
                TextFieldLink {
                    Label {
                        Text("Reply", comment: "Watch post action")
                    } icon: {
                        Image(systemName: AlohaSymbol.reply)
                    }
                } onSubmit: { typed in
                    Task { await send(reply: typed) }
                }
                .disabled(reply == .sending)

                switch reply {
                case .idle: EmptyView()
                case .sending:
                    ProgressView()
                case .sent:
                    Text("Reply sent", comment: "Watch reply status").font(.caption2)
                case .failed:
                    Text("Couldn't send the reply", comment: "Watch reply status")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Optimistic, and honest about failure: the state flips at once and
    /// flips back if the server refused.
    private func toggle(
        _ state: Binding<Bool>, on: Endpoint.StatusAction, off: Endpoint.StatusAction
    ) {
        let target = !state.wrappedValue
        state.wrappedValue = target
        Task {
            guard let client = link.client else {
                state.wrappedValue = !target
                return
            }
            do {
                _ = try await client.send(
                    Endpoint.statuses.action(status.displayed.id, target ? on : off))
            } catch {
                state.wrappedValue = !target
            }
        }
    }

    private func send(reply typed: String) async {
        guard !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let client = link.client
        else { return }
        reply = .sending
        let target = status.displayed
        let post = StatusPost(
            text: target.replyText(typed, excluding: link.credentials?.handle),
            // A reply is never less restrictive than what it answers.
            visibility: status.replyVisibility(default: .public),
            spoilerText: target.spoilerText.isEmpty ? nil : target.spoilerText,
            inReplyToID: target.id)
        do {
            _ = try await client.send(Endpoint.composing.post(post))
            reply = .sent
        } catch {
            reply = .failed
        }
    }
}
