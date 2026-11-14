// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import AlohaStore
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
    /// Whether the results on screen asked other servers. Typing never does:
    /// the server looks elsewhere only when a search is asked for, so a
    /// keystroke cannot make it fetch from another server.
    @State private var resultsResolved = false
    /// The reader's filters, in the public context: what a search finds is
    /// anyone's posts, as a public timeline is.
    @State private var verdicts = FilterVerdicts(context: .public)
    /// All kinds at once, or one kind paged (`SearchScope`).
    @State private var scope: SearchScope = .all
    /// How many results of the scope's kind the server has sent so far: the
    /// next page's `offset`. Counted as they arrive, before filters, so a
    /// hidden post does not make the next page repeat one.
    @State private var scopedOffset = 0
    @State private var hasMoreInScope = false
    @State private var isLoadingMore = false
    @State private var moreError: String?
    /// What is trending, for the empty field, where the server has trends.
    @State private var trendingTags: [Tag] = []
    @State private var trendingStatuses: [Status] = []
    @State private var didLoadTrends = false

    private var shownStatuses: [Status] { verdicts.kept(results.statuses) }

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
                trendsSections
            } else {
                // Nothing yet of what this scope shows: what another scope
                // left on screen is not an answer to this one.
                if isSearching,
                    scope.resultType.map({ results.count(of: $0) == 0 }) ?? results.isEmpty
                {
                    loadingRow
                }

                if scope.shows(.accounts), !results.accounts.isEmpty {
                    Section {
                        ForEach(
                            scope == .all
                                ? Array(results.accounts.prefix(SearchScope.allPreview))
                                : results.accounts
                        ) { account in
                            accountRow(account)
                        }
                    } header: {
                        sectionHeader(
                            Text("People", comment: "Search results section"),
                            seeAll: .accounts, count: results.accounts.count)
                    }
                }

                if scope.shows(.hashtags), !results.hashtags.isEmpty {
                    Section {
                        ForEach(
                            scope == .all
                                ? Array(results.hashtags.prefix(SearchScope.allPreview))
                                : results.hashtags
                        ) { tag in
                            hashtagRow(tag)
                        }
                    } header: {
                        sectionHeader(
                            Text("Hashtags", comment: "Search results section"),
                            seeAll: .hashtags, count: results.hashtags.count)
                    }
                }

                if scope.shows(.statuses), !shownStatuses.isEmpty {
                    Section {
                        ForEach(shownStatuses) { status in
                            statusRow(status)
                        }
                    } header: {
                        sectionHeader(
                            Text("Posts", comment: "Search results section"),
                            seeAll: .statuses, count: results.statuses.count)
                    }
                }

                if scope != .all, !isSearching, hasMoreInScope || moreError != nil {
                    moreRow
                }

                // One character is still typing, not searching: the empty
                // state waits for a query worth answering.
                if !isSearching, !resultsResolved, errorMessage == nil,
                    results.accounts.isEmpty, results.statuses.isEmpty,
                    isRemoteQuery(query.trimmingCharacters(in: .whitespacesAndNewlines))
                {
                    lookUpElsewhereRow
                }

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
        // In the content rather than `.searchScopes`: the system's scope bar
        // belongs to the active search field, and the field is put away on
        // Search so the keyboard leaves the results — taking the scopes
        // with it, just when the results arrive to be narrowed.
        .safeAreaBar(edge: .top, spacing: 0) {
            if !query.isEmpty {
                scopePicker
                    .padding(.horizontal, AlohaMetrics.space4)
                    .padding(.vertical, AlohaMetrics.space2)
            }
        }
        .environment(\.filterVerdicts, verdicts)
        .onStatusesRemoved(for: session) { removal in
            results.statuses.removeAll { removal.removes($0) }
            trendingStatuses.removeAll { removal.removes($0) }
        }
        #if os(iOS)
            .searchable(
                text: $query, isPresented: $isFieldPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("Search", comment: "Search field")
            )
            .searchPresentationToolbarBehavior(.avoidHidingContent)
        #else
            .searchable(
                text: $query, isPresented: $isFieldPresented,
                prompt: Text("Search", comment: "Search field"))
        #endif
        .navigationTitle(Text("Search", comment: "Screen title"))
        .onAppear {
            if let initialQuery, !initialQuery.isEmpty, query.isEmpty {
                // Carried in from a link or the sidebar's field: already asked.
                query = initialQuery
                schedule(initialQuery, immediately: true, resolving: true)
            } else if query.isEmpty {
                isFieldPresented = true
            }
        }
        .onChange(of: query) { _, value in schedule(value) }
        // A scope is the same question asked more narrowly, so it asks again
        // the way the search on screen was asked — resolving if that did.
        .onChange(of: scope) { _, _ in
            schedule(query, immediately: true, resolving: resultsResolved)
        }
        .onSubmit(of: .search) {
            remember(query)
            isFieldPresented = false
            schedule(query, immediately: true, resolving: true)
        }
        // A pull is somebody asking the same question again, so the search on
        // screen re-runs — every other list in the app refreshes on a pull.
        .refreshable {
            await schedule(query, immediately: true, resolving: true)?.value
        }
        .task {
            recents = SearchHistory.load()
            await loadTrends()
        }
        .onDisappear {
            searchTask?.cancel()
            searchID = UUID()
            isSearching = false
        }
    }

    private var recentsSection: some View {
        Group {
            if recents.isEmpty, trendingTags.isEmpty, trendingStatuses.isEmpty {
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

    /// What is trending, under the recent searches: something to start from
    /// when the field is empty. A server without trends (GoToSocial, a
    /// Mastodon that turned them off) answers an error or nothing, and the
    /// sections simply are not there.
    @ViewBuilder
    private var trendsSections: some View {
        if !trendingTags.isEmpty {
            Section {
                ForEach(trendingTags) { tag in
                    hashtagRow(tag)
                }
            } header: {
                Text("Trending hashtags", comment: "Search screen section, empty field")
            }
        }
        if !trendingStatuses.isEmpty {
            Section {
                ForEach(trendingStatuses) { status in
                    statusRow(status)
                }
            } header: {
                Text("Trending posts", comment: "Search screen section, empty field")
            }
        }
    }

    private var scopePicker: some View {
        Picker(selection: $scope) {
            ForEach(SearchScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        } label: {
            Text("Show", comment: "Search scope picker label")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// A section's heading, with "See all" where "All" holds results back
    /// that the section's own scope would page through.
    private func sectionHeader(
        _ title: Text, seeAll target: SearchScope, count: Int
    ) -> some View {
        HStack {
            title
            Spacer()
            if scope == .all, let type = target.resultType,
                SearchScope.hasMore(than: count, of: type)
            {
                Button {
                    scope = target
                } label: {
                    Text("See all", comment: "Search section action: show only this kind")
                }
                .font(.caption)
                .accessibilityLabel(
                    Text(
                        "See all \(target.title)",
                        comment: "Search section action. The argument is People, Hashtags or Posts."
                    ))
            }
        }
    }

    private func accountRow(_ account: Account) -> some View {
        Button {
            onAction(.openProfile(account))
        } label: {
            AccountRow(account: account, localHost: session.snapshot.instanceHost)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(palette.background)
    }

    private func hashtagRow(_ tag: Tag) -> some View {
        NavigationLink(value: Route.hashtag(tag.name)) {
            HashtagRow(tag: tag)
        }
        .listRowBackground(palette.background)
    }

    private func statusRow(_ status: Status) -> some View {
        StatusRow(
            status: status,
            policy: session.settings.sensitiveMediaPolicy,
            localHost: session.snapshot.instanceHost,
            filterWarning: verdicts.warning(for: status),
            showActions: false,
            showsCounts: session.settings.showPopularityCounts,
            onAction: onAction
        )
        .statusRowInteractions(status, session: session, onAction: onAction)
        .listRowBackground(palette.background)
    }

    /// The end of one scope's results: the next page loading as it comes
    /// into view, or why it did not, with a way to ask again.
    @ViewBuilder
    private var moreRow: some View {
        Group {
            if let moreError {
                AlohaErrorStrip(message: moreError) {
                    self.moreError = nil
                    Task { await loadMore() }
                }
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                        .accessibilityLabel(
                            Text("Loading more results", comment: "Search paging"))
                    Spacer()
                }
                .padding(.vertical, AlohaMetrics.space3)
                // Asked again after each page, so while this row stays in
                // view the pages keep coming, and once it leaves they stop.
                .task(id: "\(searchID)|\(scopedOffset)") { await loadMore() }
            }
        }
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
    }

    /// The shape of results arriving, not a spinner: three people, then a
    /// couple of lines. A lone spinner over a blank screen reads as "broken";
    /// the shape of the answer reads as "working".
    private var loadingRow: some View {
        Section {
            ForEach(0..<3, id: \.self) { index in
                searchSkeleton(avatar: index == 0)
            }
        } header: {
            if scope == .all {
                Text("People", comment: "Search results section")
            } else {
                Text(scope.title)
            }
        }
    }

    private func searchSkeleton(avatar: Bool) -> some View {
        HStack(spacing: AlohaMetrics.space3) {
            if avatar {
                Circle()
                    .fill(palette.surfaceRaised)
                    .frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.surfaceRaised)
                    .frame(width: 140, height: 12)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.surfaceRaised)
                    .frame(width: 200, height: 10)
            }
        }
        .padding(.vertical, AlohaMetrics.space2)
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
        .accessibilityHidden(true)
        .redacted(reason: .placeholder)
    }

    /// `alice.bsky.social` or `bsky.app`: a single word with at least one dot,
    /// a letter after the last one, and nothing a handle cannot hold.
    nonisolated static func looksLikeDomainHandle(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace), !text.contains("/"),
            !text.hasPrefix("#")
        else { return false }
        let labels = text.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }),
            let last = labels.last, last.count >= 2, last.allSatisfy(\.isLetter)
        else { return false }
        return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }

    private func errorStrip(_ message: String) -> some View {
        AlohaErrorStrip(message: message) {
            schedule(query, immediately: true, resolving: resultsResolved)
        }
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
    }

    /// Offered while typing a handle or a link this server does not hold:
    /// looking it up elsewhere is a request to another server, so it waits
    /// for the search to be asked for — the Search key, or this row.
    private var lookUpElsewhereRow: some View {
        Button {
            remember(query)
            schedule(query, immediately: true, resolving: true)
        } label: {
            Label {
                Text(
                    "Look up \(query.trimmingCharacters(in: .whitespacesAndNewlines)) on other servers",
                    comment: "Search action that resolves a remote handle or link")
            } icon: {
                Image(systemName: "globe")
            }
        }
        .listRowBackground(palette.background)
    }

    /// A URL or a handle can name something on another server. On Aloha
    /// Social that includes a bare Bluesky handle, which has dots and no `@`
    /// (`alice.bsky.social`): the server resolves it like any other
    /// (`CacheActorService`), but only when asked to.
    private func isRemoteQuery(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("http") || trimmed.dropFirst().contains("@")
            || (session.capabilities.isNextcloudSocial && Self.looksLikeDomainHandle(trimmed))
    }

    /// Signs up a run of the search on screen. Returns it, so a caller with
    /// something to wait for — the pull-to-refresh gesture — can.
    ///
    /// `resolving` is for a search somebody asked for. Aloha Social looks
    /// other servers up only then (`resolve` on submit, never while typing),
    /// which Mastodon asks of its clients too.
    @discardableResult
    private func schedule(
        _ value: String, immediately: Bool = false, resolving: Bool = false
    ) -> Task<Void, Never>? {
        searchTask?.cancel()
        let id = UUID()
        searchID = id
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            isSearching = false
            results = SearchResults()
            resultsResolved = false
            errorMessage = nil
            hasMoreInScope = false
            moreError = nil
            return nil
        }
        isSearching = true
        errorMessage = nil
        searchTask = Task {
            if !immediately { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await search(trimmed, id: id, resolving: resolving, scope: scope)
        }
        return searchTask
    }

    private func search(
        _ value: String, id: UUID, resolving: Bool, scope: SearchScope
    ) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            isSearching = false
            results = SearchResults()
            resultsResolved = false
            errorMessage = nil
            return
        }
        isSearching = true
        // Only the search still matching what is on screen may put the
        // spinner down; a newer one owns it from here.
        defer { if searchID == id { isSearching = false } }

        // Resolved through the reading account's own server, so a remote post
        // opens with working action buttons.
        let resolve = resolving && isRemoteQuery(trimmed)

        do {
            let endpoint =
                scope.resultType.map {
                    Endpoint.search.page(
                        trimmed, type: $0, limit: SearchScope.pageSize, resolve: resolve)
                }
                ?? Endpoint.search.search(trimmed, resolve: resolve, limit: SearchScope.allLimit)
            let response = try await session.client.decode(SearchResults.self, from: endpoint)
            await verdicts.prepare(response.statuses, session: session)
            guard !Task.isCancelled, searchID == id else { return }
            results = response
            resultsResolved = resolve
            errorMessage = nil
            moreError = nil
            if let type = scope.resultType {
                scopedOffset = response.count(of: type)
                hasMoreInScope = SearchPaging.mayHaveMore(received: scopedOffset)
            } else {
                scopedOffset = 0
                hasMoreInScope = false
            }
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

    /// The next page of the scope on screen. Never resolving: other
    /// servers were asked, if at all, by the first page. A newer search
    /// meanwhile — a keystroke, another scope — owns the screen, and this
    /// page is dropped.
    private func loadMore() async {
        guard let type = scope.resultType, hasMoreInScope, !isLoadingMore else { return }
        let id = searchID
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let offset = scopedOffset
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await session.client.decode(
                SearchResults.self,
                from: Endpoint.search.page(
                    trimmed, type: type, offset: offset, limit: SearchScope.pageSize))
            await verdicts.prepare(page.statuses, session: session)
            guard !Task.isCancelled, searchID == id else { return }
            let received = page.count(of: type)
            results = SearchPaging.appending(page, to: results, type: type)
            scopedOffset = offset + received
            hasMoreInScope = SearchPaging.mayHaveMore(received: received)
            moreError = nil
        } catch {
            guard !Task.isCancelled, searchID == id else { return }
            await session.handle(error)
            moreError =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "More results could not be loaded. Try again.",
                    comment: "Search paging failure")
        }
    }

    /// Trending hashtags and posts for the empty field, once per visit.
    /// Both are optional: a server that has no trends, or refuses them,
    /// leaves the recent searches on their own rather than an error.
    private func loadTrends() async {
        guard !didLoadTrends else { return }
        didLoadTrends = true
        async let tags = try? await session.client.decode(
            LossyArray<Tag>.self, from: Endpoint.search.trendingTags(limit: 10))
        async let posts = try? await session.client.decode(
            LossyArray<Status>.self, from: Endpoint.discovery.trendingStatuses(limit: 5))
        let (tagPage, postPage) = await (tags, posts)
        let statuses = postPage?.elements ?? []
        await verdicts.prepare(statuses, session: session)
        guard !Task.isCancelled else {
            didLoadTrends = false
            return
        }
        trendingTags = tagPage?.elements ?? []
        trendingStatuses = verdicts.kept(statuses)
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
                    EmojiLabel(
                        account.bestDisplayName, emojis: account.emojis, relativeTo: .subheadline
                    )
                    .font(.subheadline.weight(.medium))
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
