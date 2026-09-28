// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Accounts, as a moderator sees them: who is silenced, who is suspended, and
/// the way back from either.
///
/// Mastodon's `/api/v1/admin/accounts`. Its `email` and `ip` filters are
/// accepted by the server and match nothing — it holds neither for a fediverse
/// account — so they are not offered here rather than offered and useless.
public struct ModerationAccountsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var accounts: [AdminAccount] = []
    @State private var origin: Endpoint.moderation.Origin = .any
    @State private var standing: Endpoint.moderation.Standing = .any
    @State private var query = ""
    @State private var isLoading = true
    @State private var acting: AdminAccount?
    @State private var errorMessage: String?

    public init(session: AccountSession, onAction: @escaping (StatusRowAction) -> Void) {
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(palette.destructive)
            }

            Section {
                Picker(selection: $origin) {
                    Text("Everyone", comment: "Moderation origin filter").tag(
                        Endpoint.moderation.Origin.any)
                    Text("Here", comment: "Moderation origin filter").tag(
                        Endpoint.moderation.Origin.local)
                    Text("Elsewhere", comment: "Moderation origin filter").tag(
                        Endpoint.moderation.Origin.remote)
                } label: {
                    Text("From", comment: "Moderation filter")
                }
                .pickerStyle(.segmented)

                Picker(selection: $standing) {
                    Text("Any standing", comment: "Moderation standing filter").tag(
                        Endpoint.moderation.Standing.any)
                    Text("Active", comment: "Moderation standing filter").tag(
                        Endpoint.moderation.Standing.active)
                    Text("Silenced", comment: "Moderation standing filter").tag(
                        Endpoint.moderation.Standing.silenced)
                    Text("Suspended", comment: "Moderation standing filter").tag(
                        Endpoint.moderation.Standing.suspended)
                } label: {
                    Text("Standing", comment: "Moderation filter")
                }
            }

            Section {
                ForEach(accounts) { entry in
                    Button {
                        acting = entry
                    } label: {
                        AdminAccountRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }

                if accounts.isEmpty && !isLoading {
                    Text("Nobody matches that.", comment: "Moderation accounts empty")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryLabel)
                }
            }
        }
        .navigationTitle(Text("Accounts", comment: "Screen title"))
        .searchable(
            text: $query,
            prompt: Text("Username", comment: "Moderation account search prompt")
        )
        .refreshable { await load() }
        .task(id: filterKey) { await load() }
        .sheet(item: $acting) { entry in
            ModerationAccountSheet(entry: entry, session: session, onAction: onAction) {
                Task { await load() }
            }
        }
    }

    private var filterKey: String {
        "\(origin.rawValue)|\(standing.rawValue)|\(query)"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        // A keystroke should not be a request.
        if !query.isEmpty {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
        }
        do {
            accounts = try await session.client.decode(
                LossyArray<AdminAccount>.self,
                from: Endpoint.moderation.accounts(
                    origin: origin, standing: standing,
                    username: query.trimmingCharacters(in: .whitespaces), limit: 40)
            ).elements
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}

struct AdminAccountRow: View {
    @Environment(\.alohaPalette) private var palette

    let entry: AdminAccount

    var body: some View {
        HStack(spacing: AlohaMetrics.space3) {
            if let account = entry.account {
                AvatarView(account: account, size: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.account?.bestDisplayName ?? entry.username)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(verbatim: entry.handle)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            badge
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var badge: some View {
        switch entry.standing {
        case .active:
            EmptyView()
        case .silenced:
            label(Text("Silenced", comment: "Account standing"), palette.boost)
        case .suspended:
            label(Text("Suspended", comment: "Account standing"), palette.destructive)
        case .sensitized:
            label(Text("Marked sensitive", comment: "Account standing"), palette.secondaryLabel)
        }
    }

    private func label(_ text: Text, _ colour: Color) -> some View {
        text
            .font(AlohaType.micro)
            .foregroundStyle(colour)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(colour.opacity(0.14), in: Capsule())
    }
}

/// What can be done to one account, and the way back from each of them.
struct ModerationAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alohaPalette) private var palette

    let entry: AdminAccount
    let session: AccountSession
    let onAction: (StatusRowAction) -> Void
    let onChange: () -> Void

    @State private var note = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(palette.destructive)
                }

                Section {
                    AdminAccountRow(entry: entry)
                    if let account = entry.account {
                        Button {
                            dismiss()
                            onAction(.openProfile(account))
                        } label: {
                            Text("Open profile", comment: "Moderation action")
                        }
                    }
                }

                Section {
                    TextField(
                        text: $note,
                        prompt: Text("Why, for the record", comment: "Moderation note prompt")
                    ) {
                        Text("Note", comment: "Moderation field")
                    }

                    if entry.silenced {
                        Button {
                            Task { await run(Endpoint.moderation.unsilence(entry.id)) }
                        } label: {
                            Text("Lift the silence", comment: "Moderation action")
                        }
                    } else {
                        Button {
                            Task { await act(.silence) }
                        } label: {
                            Text("Silence", comment: "Moderation action")
                        }
                    }

                    if entry.suspended {
                        Button {
                            Task { await run(Endpoint.moderation.unsuspend(entry.id)) }
                        } label: {
                            Text("Lift the suspension", comment: "Moderation action")
                        }
                    } else {
                        Button(role: .destructive) {
                            Task { await act(.suspend) }
                        } label: {
                            Text("Suspend", comment: "Moderation action")
                        }
                    }

                    if entry.sensitized {
                        Button {
                            Task { await run(Endpoint.moderation.unsensitive(entry.id)) }
                        } label: {
                            Text(
                                "Stop forcing warnings on their media", comment: "Moderation action"
                            )
                        }
                    }
                } header: {
                    Text("Decide", comment: "Moderation section")
                } footer: {
                    Text(
                        "Silencing keeps their posts from anyone who does not follow them. Suspending stops them being delivered or shown at all.",
                        comment: "Moderation decisions explanation")
                }
                .disabled(isWorking)
            }
            .navigationTitle(Text(verbatim: entry.handle))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Close", comment: "Sheet action")
                    }
                }
            }
        }
    }

    private func act(_ action: AdminAccountAction) async {
        await run(Endpoint.moderation.act(on: entry.id, action: action, note: note))
    }

    private func run(_ endpoint: Endpoint) async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await session.client.send(endpoint)
            onChange()
            dismiss()
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}

// MARK: - Trends

/// What may trend: the three readers a moderator sees, and a button that keeps
/// something out of Explore.
///
/// **Rejecting hides; approving grants nothing.** Trending on this server shows
/// everything nobody has objected to — the other arrangement would have emptied
/// every instance's Explore page on upgrade — so an approval only records that
/// a moderator has looked. The screen says so rather than implying a queue that
/// does not exist.
public struct ModerationTrendsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var kind: Endpoint.moderation.TrendKind = .tags
    @State private var tags: [Tag] = []
    @State private var statuses: [Status] = []
    @State private var links: [Card] = []
    @State private var decided: Set<String> = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init(session: AccountSession, onAction: @escaping (StatusRowAction) -> Void) {
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(palette.destructive)
            }

            Picker(selection: $kind) {
                Text("Hashtags", comment: "Trends filter").tag(Endpoint.moderation.TrendKind.tags)
                Text("Posts", comment: "Trends filter").tag(Endpoint.moderation.TrendKind.statuses)
                Text("Links", comment: "Trends filter").tag(Endpoint.moderation.TrendKind.links)
            } label: {
                Text("Show", comment: "Trends filter")
            }
            .pickerStyle(.segmented)
            .listRowBackground(palette.background)

            Section {
                switch kind {
                case .tags:
                    ForEach(tags) { tag in
                        row(id: tag.name, label: Text(verbatim: "#\(tag.name)"), open: nil)
                    }
                case .statuses:
                    ForEach(statuses) { status in
                        row(
                            id: status.id,
                            label: Text(StatusHTMLParser().plainText(status.displayed.content))
                        ) {
                            onAction(.open(status))
                        }
                    }
                case .links:
                    ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                        row(id: link.url?.absoluteString ?? link.title, label: Text(link.title)) {
                            onAction(.openCard(link))
                        }
                    }
                }

                if isEmpty && !isLoading {
                    Text("Nothing is trending here yet.", comment: "Trends empty")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryLabel)
                }
            } footer: {
                Text(
                    "Everything nobody has objected to trends already, so approving only records that you have looked. Rejecting is what keeps something out of Explore.",
                    comment: "Trends moderation explanation")
            }
        }
        .navigationTitle(Text("What may trend", comment: "Screen title"))
        .refreshable { await load() }
        .task(id: kind) { await load() }
    }

    private var isEmpty: Bool {
        switch kind {
        case .tags: tags.isEmpty
        case .statuses: statuses.isEmpty
        case .links: links.isEmpty
        }
    }

    /// `open` is absent for a hashtag, which is a navigation rather than an
    /// action and gets a real link so it pushes like every other one.
    @ViewBuilder
    private func row(id: String, label: Text, open: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            if let open {
                Button(action: open) {
                    label
                        .font(.subheadline)
                        .foregroundStyle(palette.label)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: Route.hashtag(id)) {
                    label
                        .font(.subheadline)
                        .foregroundStyle(palette.label)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            if decided.contains(id) {
                Text("Decided", comment: "Trend decision badge")
                    .font(AlohaType.micro)
                    .foregroundStyle(palette.secondaryLabel)
            } else {
                HStack(spacing: AlohaMetrics.space3) {
                    Button {
                        Task { await decide(id: id, approve: true) }
                    } label: {
                        Text("Looked at it", comment: "Trend decision")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        Task { await decide(id: id, approve: false) }
                    } label: {
                        Text("Keep it out", comment: "Trend decision")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func decide(id: String, approve: Bool) async {
        let encoded =
            id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        let endpoint =
            approve
            ? Endpoint.moderation.approveTrend(kind, id: encoded)
            : Endpoint.moderation.rejectTrend(kind, id: encoded)
        do {
            _ = try await session.client.send(endpoint)
            decided.insert(id)
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        decided = []
        do {
            switch kind {
            case .tags:
                tags = try await session.client.decode(
                    LossyArray<Tag>.self, from: Endpoint.moderation.trendingTags()
                ).elements
            case .statuses:
                statuses = try await session.client.decode(
                    LossyArray<Status>.self, from: Endpoint.moderation.trendingStatuses()
                ).elements
            case .links:
                links = try await session.client.decode(
                    LossyArray<Card>.self, from: Endpoint.moderation.trendingLinks()
                ).elements
            }
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
