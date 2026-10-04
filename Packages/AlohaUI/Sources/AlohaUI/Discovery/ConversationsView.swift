// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Direct messages, one row per conversation (docs/05 §8), laid out the way
/// Nextcloud Social lays out its Messages page: a New message button, a
/// search field, an All / Unread filter, and rows of avatar, name, time,
/// preview and an unread dot. A row opens the thread.
///
/// This screen used to be `timelines/direct` — a flat list of every direct
/// status, with no grouping and no unread state. Mastodon deprecated that
/// endpoint in 3.0, so on newer servers it also returned nothing at all.
public struct ConversationsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void
    private let onOpen: (Route) -> Void

    @State private var conversations: [Conversation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var isComposing = false

    enum Filter: Hashable {
        case all, unread
    }

    public init(
        session: AccountSession,
        onAction: @escaping (StatusRowAction) -> Void,
        onOpen: @escaping (Route) -> Void = { _ in }
    ) {
        self.session = session
        self.onAction = onAction
        self.onOpen = onOpen
    }

    private var unreadCount: Int { conversations.filter(\.unread).count }

    private var visible: [Conversation] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        return conversations.filter { conversation in
            if filter == .unread && !conversation.unread { return false }
            guard !trimmed.isEmpty else { return true }
            if participants(conversation).lowercased().contains(trimmed) { return true }
            if conversation.accounts.contains(where: { $0.acct.lowercased().contains(trimmed) }) {
                return true
            }
            return conversation.lastStatus.map { preview($0).lowercased().contains(trimmed) }
                ?? false
        }
    }

    public var body: some View {
        List {
            Section {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(palette.destructive)
                }

                ForEach(visible) { conversation in
                    Button {
                        open(conversation)
                    } label: {
                        row(conversation)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(
                        EdgeInsets(
                            top: AlohaMetrics.space2, leading: AlohaMetrics.space3,
                            bottom: AlohaMetrics.space2, trailing: AlohaMetrics.space3)
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await delete(conversation) }
                        } label: {
                            Label {
                                Text("Delete", comment: "Conversations action")
                            } icon: {
                                Image(systemName: AlohaSymbol.delete)
                            }
                        }
                    }
                }

                if visible.isEmpty && !isLoading { emptyState }
            } header: {
                filterBar
            }
        }
        .listStyle(.plain)
        .overlay {
            if isLoading && conversations.isEmpty {
                ProgressView("Loading messages…")
            }
        }
        .searchable(
            text: $query,
            prompt: Text("Search conversations", comment: "Conversations search prompt")
        )
        .navigationTitle(Text("Messages", comment: "Screen title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isComposing = true
                } label: {
                    Label {
                        Text("New message", comment: "Conversations action")
                    } icon: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                .accessibilityLabel(Text("New message", comment: "Conversations action"))
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    Task { await markAllRead() }
                } label: {
                    Label {
                        Text("Mark all as read", comment: "Conversations action")
                    } icon: {
                        Image(systemName: "envelope.open")
                    }
                }
                .disabled(unreadCount == 0)
            }
        }
        .sheet(isPresented: $isComposing) {
            NewMessageView(session: session) { account in
                startConversation(with: account)
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    // MARK: - Actions

    /// Takes the conversation off the list. Neither side's messages are
    /// deleted, here or there, and a later message in the same thread brings it
    /// back — which is what the server's own docblock says it does, and worth
    /// saying because "delete" reads stronger than it is.
    private func delete(_ conversation: Conversation) async {
        let previous = conversations
        conversations.removeAll { $0.id == conversation.id }
        do {
            _ = try await session.client.send(
                Endpoint.timelines.deleteConversation(conversation.id))
        } catch {
            conversations = previous
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func markAllRead() async {
        let previous = conversations
        for index in conversations.indices { conversations[index].unread = false }
        do {
            _ = try await session.client.send(Endpoint.timelines.markAllConversationsRead)
        } catch {
            conversations = previous
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    // MARK: - Pieces

    private var filterBar: some View {
        Picker(selection: $filter) {
            Text("All", comment: "Conversations filter").tag(Filter.all)
            Text("Unread (\(unreadCount))", comment: "Conversations filter with count")
                .tag(Filter.unread)
        } label: {
            Text("Filter", comment: "Conversations filter picker")
        }
        .pickerStyle(.segmented)
        .textCase(nil)
        .padding(.horizontal, AlohaMetrics.space3)
        .padding(.vertical, AlohaMetrics.space1)
        .listRowInsets(EdgeInsets())
        .background(palette.background)
    }

    private func row(_ conversation: Conversation) -> some View {
        HStack(alignment: .center, spacing: AlohaMetrics.space3) {
            ConversationAvatar(accounts: conversation.accounts, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: AlohaMetrics.space2) {
                    Text(participants(conversation))
                        .font(.subheadline.weight(conversation.unread ? .bold : .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let date = conversation.lastStatus?.createdAt {
                        Text(PostAge.short(date))
                            .font(AlohaType.meta)
                            .foregroundStyle(palette.tertiaryLabel)
                    }
                }

                if let last = conversation.lastStatus {
                    Text(previewLine(last))
                        .font(.footnote)
                        .foregroundStyle(
                            conversation.unread ? palette.label : palette.secondaryLabel
                        )
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("No messages yet", comment: "Conversation without a message")
                        .font(.footnote)
                        .foregroundStyle(palette.tertiaryLabel)
                }
            }

            // Unread is a dot *and* bold text: colour is never the only signal
            // (docs/12 §3).
            Circle()
                .fill(conversation.unread ? palette.accent : .clear)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(conversation))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            if filter == .unread {
                Text("No unread messages", comment: "Empty unread conversations")
            } else if !query.isEmpty {
                Text("No conversations found", comment: "Empty conversations search")
            } else {
                Text("No conversations", comment: "Empty conversations")
            }
        } description: {
            if filter == .all && query.isEmpty {
                Text(
                    "Direct messages you send and receive appear here.",
                    comment: "Empty conversations detail")
            }
        } actions: {
            if filter == .all && query.isEmpty {
                Button {
                    isComposing = true
                } label: {
                    Text("Start a conversation", comment: "Empty conversations action")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .listRowSeparator(.hidden)
    }

    // MARK: - Text

    private func participants(_ conversation: Conversation) -> String {
        let names = conversation.accounts.map(\.bestDisplayName)
        if names.isEmpty {
            return String(localized: "You", comment: "Conversation with nobody else")
        }
        return names.formatted(.list(type: .and))
    }

    private func preview(_ status: Status) -> String {
        if !status.spoilerText.isEmpty { return status.spoilerText }
        let text = StatusHTMLParser().plainText(status.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, !status.mediaAttachments.isEmpty {
            return String(
                localized: "^[\(status.mediaAttachments.count) attachment](inflect: true)",
                comment: "Conversation preview with media only")
        }
        return text
    }

    /// Your own last message is prefixed the way a chat list prefixes it.
    private func previewLine(_ status: Status) -> String {
        let body = preview(status)
        if status.account.id == session.snapshot.serverAccountID {
            return String(localized: "You: \(body)", comment: "Conversation preview of own message")
        }
        return body
    }

    private func accessibilityLabel(_ conversation: Conversation) -> Text {
        let who = participants(conversation)
        let body = conversation.lastStatus.map(previewLine) ?? ""
        if conversation.unread {
            return Text("Unread. \(who). \(body)", comment: "Unread conversation")
        }
        return Text("\(who). \(body)", comment: "Conversation")
    }

    // MARK: - Actions

    /// Opening marks it read on the server and here, so the dot goes at once
    /// rather than on the next refresh.
    private func open(_ conversation: Conversation) {
        onOpen(.conversation(conversation))
        guard conversation.unread else { return }

        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index].unread = false
        }
        Task {
            _ = try? await session.client.send(
                Endpoint.timelines.markConversationRead(conversation.id))
        }
    }

    /// A conversation that already exists with exactly this person is reused;
    /// otherwise the thread opens empty with the composer ready.
    private func startConversation(with account: Account) {
        isComposing = false
        if let existing = conversations.first(where: {
            $0.accounts.count == 1 && $0.accounts.first?.id == account.id
        }) {
            open(existing)
        } else {
            onOpen(.conversation(Conversation(id: "new-\(account.id)", accounts: [account])))
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await session.client.decode(
                LossyArray<Conversation>.self, from: Endpoint.timelines.conversations())
            conversations = page.elements
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
                ?? String(localized: "Messages could not be loaded. Pull down to try again.")
        }
    }
}

/// One avatar for a one-to-one conversation; two stacked for a group.
struct ConversationAvatar: View {
    let accounts: [Account]
    let size: Double

    var body: some View {
        if accounts.count > 1, let first = accounts.first, let second = accounts.dropFirst().first {
            ZStack(alignment: .topLeading) {
                AvatarView(account: second, size: size * 0.7)
                    .offset(x: size * 0.3, y: size * 0.3)
                AvatarView(account: first, size: size * 0.7)
            }
            .frame(width: size, height: size)
        } else if let first = accounts.first {
            AvatarView(account: first, size: size)
        } else {
            Image(systemName: AlohaSymbol.envelope)
                .font(.title3)
                .frame(width: size, height: size)
                .background(.quaternary, in: Circle())
        }
    }
}

/// Who to write to. Searches the server; results are people you know first.
struct NewMessageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession
    let onPick: (Account) -> Void

    @State private var query = ""
    @State private var results: [Account] = []
    @State private var isSearching = false
    /// Mutual follows, which is who most messages go to. Offered before a
    /// search rather than after it: making somebody search for a person the
    /// app could have listed is a step that answers its own question.
    @State private var mutuals: [Account] = []

    private var isSearchEmpty: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if isSearchEmpty, !mutuals.isEmpty {
                    SwiftUI.Section {
                        ForEach(mutuals) { account in
                            personRow(account)
                        }
                    } header: {
                        Text("People you both follow", comment: "New message section")
                    }
                }

                if results.isEmpty && !query.isEmpty && !isSearching {
                    Text("Nobody found.", comment: "New message empty search")
                        .font(.footnote)
                        .foregroundStyle(palette.tertiaryLabel)
                } else if results.isEmpty && mutuals.isEmpty {
                    Text(
                        "Search for someone to write to.",
                        comment: "New message search hint"
                    )
                    .font(.footnote)
                    .foregroundStyle(palette.tertiaryLabel)
                }

                ForEach(results) { account in
                    Button {
                        onPick(account)
                    } label: {
                        HStack(spacing: AlohaMetrics.space3) {
                            AvatarView(account: account, size: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(account.bestDisplayName)
                                    .font(AlohaType.name)
                                    .lineLimit(1)
                                Text(
                                    account.qualifiedHandle(
                                        localHost: session.snapshot.instanceHost)
                                )
                                .font(AlohaType.meta)
                                .foregroundStyle(palette.tertiaryLabel)
                                .lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(account.bestDisplayName))
                }
            }
            .listStyle(.plain)
            .searchable(
                text: $query,
                prompt: Text("Search people", comment: "New message search prompt")
            )
            .navigationTitle(Text("New message", comment: "Screen title"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", comment: "Sheet action")
                    }
                }
            }
            .task(id: query) { await search() }
            .task { await loadMutuals() }
        }
    }

    /// Nextcloud Social's `direct/compose/mutuals`. Absent on a plain Mastodon
    /// server, where the section simply does not appear.
    private func loadMutuals() async {
        mutuals =
            (try? await session.client.decode(
                LossyArray<Account>.self, from: Endpoint.timelines.directMessageMutuals))?
            .elements ?? []
    }

    @ViewBuilder
    private func personRow(_ account: Account) -> some View {
        Button {
            onPick(account)
        } label: {
            HStack(spacing: AlohaMetrics.space3) {
                AvatarView(account: account, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.bestDisplayName)
                        .font(AlohaType.name)
                        .lineLimit(1)
                    Text(account.qualifiedHandle(localHost: session.snapshot.instanceHost))
                        .font(AlohaType.meta)
                        .foregroundStyle(palette.tertiaryLabel)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(account.bestDisplayName))
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        // Wait for typing to settle before every keystroke becomes a request.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        let found = try? await session.client.decode(
            SearchResults.self,
            from: Endpoint.search.search(trimmed, type: "accounts", resolve: true, limit: 20))
        guard !Task.isCancelled else { return }
        results = (found?.accounts ?? []).filter { $0.id != session.snapshot.serverAccountID }
    }
}
