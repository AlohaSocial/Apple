// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

public struct SearchView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void
    private let initialQuery: String?

    @State private var query = ""
    @State private var results = SearchResults()
    @State private var recents: [String] = []
    @State private var isSearching = false
    @State private var isFieldPresented = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var searchID = UUID()

    /// A query carried in from somewhere else — the sidebar's field, a deep
    /// link, a shared URL. `Route.search(query:)` has always carried one; this
    /// view simply never took it.
    public init(
        session: AccountSession, initialQuery: String? = nil,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.session = session
        self.onAction = onAction
        self.initialQuery = initialQuery
    }

    public var body: some View {
        List {
            if let errorMessage {
                errorStrip(errorMessage)
            }

            if query.isEmpty {
                recentsSection
            } else {
                if isSearching, results.isEmpty {
                    loadingRow
                }

                if !results.accounts.isEmpty {
                    Section {
                        ForEach(results.accounts) { account in
                            Button {
                                onAction(.openProfile(account))
                            } label: {
                                AccountRow(
                                    account: account, localHost: session.snapshot.instanceHost
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(palette.background)
                        }
                    } header: {
                        Text("People", comment: "Search results section")
                    }
                }

                if !results.hashtags.isEmpty {
                    Section {
                        ForEach(results.hashtags) { tag in
                            NavigationLink(value: Route.hashtag(tag.name)) {
                                HashtagRow(tag: tag)
                            }
                            .listRowBackground(palette.background)
                        }
                    } header: {
                        Text("Hashtags", comment: "Search results section")
                    }
                }

                if !results.statuses.isEmpty {
                    Section {
                        ForEach(results.statuses) { status in
                            StatusRow(
                                status: status,
                                policy: session.settings.sensitiveMediaPolicy,
                                localHost: session.snapshot.instanceHost,
                                showActions: false,
                                showsCounts: session.settings.showPopularityCounts,
                                onAction: onAction
                            )
                            .listRowBackground(palette.background)
                        }
                    } header: {
                        Text("Posts", comment: "Search results section")
                    }
                }

                // One character is still typing, not searching: the empty
                // state waits for a query worth answering.
                if !isSearching, results.isEmpty, errorMessage == nil, query.count >= 2 {
                    ContentUnavailableView {
                        Text("Nothing found", comment: "Empty search")
                    } description: {
                        Text(
                            "Try a handle, a hashtag, or paste a link to a post.",
                            comment: "Empty search hint")
                    }
                    .listRowBackground(palette.background)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .alohaGround(palette)
        #if os(iOS)
            .searchable(
                text: $query, isPresented: $isFieldPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("Search", comment: "Search field"))
        #else
            .searchable(
                text: $query, isPresented: $isFieldPresented,
                prompt: Text("Search", comment: "Search field"))
        #endif
        .navigationTitle(Text("Search", comment: "Screen title"))
        .onAppear {
            if let initialQuery, !initialQuery.isEmpty, query.isEmpty {
                query = initialQuery
                schedule(initialQuery)
            } else if query.isEmpty {
                isFieldPresented = true
            }
        }
        .onChange(of: query) { _, value in schedule(value) }
        .onSubmit(of: .search) { remember(query) }
        // A pull is somebody asking the same question again, so the search on
        // screen re-runs — every other list in the app refreshes on a pull.
        .refreshable {
            await schedule(query, immediately: true)?.value
        }
        .task { recents = SearchHistory.load() }
        .onDisappear {
            searchTask?.cancel()
            searchID = UUID()
            isSearching = false
        }
    }

    private var recentsSection: some View {
        Group {
            if recents.isEmpty {
                ContentUnavailableView {
                    Text("Search the fediverse", comment: "Search placeholder title")
                } description: {
                    Text(
                        "People, hashtags, posts — or paste a link and it will open here.",
                        comment: "Search placeholder detail")
                }
                .listRowBackground(palette.background)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(recents, id: \.self) { recent in
                        Button {
                            query = recent
                        } label: {
                            Label {
                                Text(recent)
                            } icon: {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(palette.background)
                    }
                } header: {
                    HStack {
                        Text("Recent", comment: "Search history section")
                        Spacer()
                        Button {
                            SearchHistory.clear()
                            recents = []
                        } label: {
                            Text("Clear", comment: "Search history action")
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
    }

    private func errorStrip(_ message: String) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.warning)
            Text(message).font(.footnote)
            Spacer()
            Button {
                schedule(query, immediately: true)
            } label: {
                Text("Retry", comment: "Search reload action")
            }
            .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(palette.destructive)
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
    }

    /// Signs up a run of the search on screen. Returns it, so a caller with
    /// something to wait for — the pull-to-refresh gesture — can.
    @discardableResult
    private func schedule(_ value: String, immediately: Bool = false) -> Task<Void, Never>? {
        searchTask?.cancel()
        let id = UUID()
        searchID = id
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            isSearching = false
            results = SearchResults()
            errorMessage = nil
            return nil
        }
        isSearching = true
        errorMessage = nil
        searchTask = Task {
            if !immediately { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await search(trimmed, id: id)
        }
        return searchTask
    }

    private func search(_ value: String, id: UUID) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            isSearching = false
            results = SearchResults()
            errorMessage = nil
            return
        }
        isSearching = true
        // Only the search still matching what is on screen may put the
        // spinner down; a newer one owns it from here.
        defer { if searchID == id { isSearching = false } }

        // A URL or a handle is resolved through the reading account's own
        // server, so a remote post opens with working action buttons.
        let looksRemote = trimmed.hasPrefix("http") || trimmed.contains("@")

        do {
            let response = try await session.client.decode(
                SearchResults.self,
                from: Endpoint.search.search(trimmed, resolve: looksRemote, limit: 20))
            guard !Task.isCancelled, searchID == id else { return }
            results = response
            errorMessage = nil
        } catch {
            // Superseded by the next keystroke, not a failure.
            guard !Task.isCancelled, searchID == id else { return }
            await session.handle(error)
            guard !Task.isCancelled, searchID == id else { return }
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "Search could not be run. Try again.",
                    comment: "Search failure")
        }
    }

    private func remember(_ value: String) {
        guard value.count >= 2 else { return }
        recents = SearchHistory.remember(value)
    }
}

/// Recent searches, stored locally and clearable. Nothing else about a search
/// is kept (docs/04 §7).
enum SearchHistory {
    private static let key = "aloha.searchHistory"
    private static let limit = 10

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func remember(_ value: String) -> [String] {
        var history = load().filter { $0.caseInsensitiveCompare(value) != .orderedSame }
        history.insert(value, at: 0)
        history = Array(history.prefix(limit))
        UserDefaults.standard.set(history, forKey: key)
        return history
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

public struct AccountRow: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics

    private let account: Account
    private let localHost: String?

    public init(account: Account, localHost: String?) {
        self.account = account
        self.localHost = localHost
    }

    public var body: some View {
        HStack(spacing: AlohaMetrics.space3) {
            AvatarView(account: account, size: metrics.avatarSize)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AlohaMetrics.space1) {
                    Text(account.bestDisplayName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if account.bot {
                        Image(systemName: "gearshape.2")
                            .font(.caption2)
                            .foregroundStyle(palette.tertiaryLabel)
                    }
                }
                Text(account.qualifiedHandle(localHost: localHost))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

public struct HashtagRow: View {
    @Environment(\.alohaPalette) private var palette

    private let tag: Tag

    public init(tag: Tag) {
        self.tag = tag
    }

    public var body: some View {
        HStack(spacing: AlohaMetrics.space3) {
            Image(systemName: AlohaSymbol.hashtag)
                .foregroundStyle(palette.hashtag)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "#\(tag.name)").font(.subheadline.weight(.medium))
                // Nextcloud Social sends a single bucket and always `accounts: 0`
                // — it counts uses, not distinct accounts. So uses only, and no
                // sparkline drawn from one point (docs/05 §7).
                if tag.totalUses > 0 {
                    Text("^[\(tag.totalUses) post](inflect: true)", comment: "Hashtag usage count")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
