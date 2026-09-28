// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Discover, the way Nextcloud Social lays it out: a switcher across People,
/// Starter packs, Pictures, Videos and Hashtags, with the curated categories
/// as a row of chips above whichever is showing.
///
/// Every Nextcloud-only section is gated on the capability and the screen is
/// still whole with all of them absent: suggestions, trending tags and links
/// are Mastodon's own.
public struct ExploreView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    enum Section: String, CaseIterable, Identifiable {
        case people, packs, pictures, videos, hashtags
        var id: String { rawValue }
    }

    @State private var section: Section = .people
    @State private var categories: [DiscoverCategory] = []
    @State private var selectedCategory: DiscoverCategory?

    // People
    @State private var query = ""
    @State private var found: [Account] = []
    @State private var foundElsewhere: DirectorySearchResults = DirectorySearchResults()
    @State private var isSearching = false
    @State private var followGraph: FollowGraph?
    /// Remembered per device: somebody who likes the picture keeps it, and
    /// somebody who does not never sees it again.
    @AppStorage("aloha.discover.constellation") private var showsConstellation = false
    @State private var suggestions: [Suggestion] = []
    @State private var popular: [Account] = []
    @State private var directories: [DirectorySource] = []
    /// This instance's own profile directory — the accounts here that chose to
    /// be listed. Separate from `directories`, which is the list of *other*
    /// servers this one will ask about people.
    @State private var directory: [Account] = []
    @State private var directoryOrder: Endpoint.search.DirectoryOrder = .active

    // Hashtags
    @State private var trendingTags: [Tag] = []
    @State private var elsewhereTags: [Tag] = []
    @State private var trendingLinks: [Card] = []
    @State private var followedTags: Set<String> = []
    @State private var period = "1d"

    @State private var isLoading = true

    public init(session: AccountSession, onAction: @escaping (StatusRowAction) -> Void) {
        self.session = session
        self.onAction = onAction
    }

    private var isNextcloud: Bool { session.capabilities.isNextcloudSocial }

    private var sections: [Section] {
        isNextcloud ? Section.allCases : [.people, .pictures, .videos, .hashtags]
    }

    public var body: some View {
        VStack(spacing: 0) {
            switcher
            if !categories.isEmpty { categoryChips }
            Divider()

            Group {
                switch section {
                case .people: people
                case .packs: StarterPacksView(session: session, onAction: onAction)
                case .pictures:
                    DiscoverMediaGrid(session: session, media: .image, onAction: onAction)
                case .videos:
                    DiscoverMediaGrid(session: session, media: .video, onAction: onAction)
                case .hashtags: hashtags
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(palette.background)
        .navigationTitle(Text("Discover", comment: "Screen title"))
        .task { await load() }
        .task(id: directoryOrder) { await loadDirectory() }
        .onChange(of: period) { _, _ in Task { await loadTrendingTags() } }
        .task(id: query) { await search() }
    }

    // MARK: - Chrome

    private var switcher: some View {
        Picker(selection: $section) {
            ForEach(sections) { option in
                title(for: option).tag(option)
            }
        } label: {
            Text("Section", comment: "Discover section picker")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, AlohaMetrics.space3)
        .padding(.vertical, AlohaMetrics.space2)
    }

    private func title(for section: Section) -> Text {
        switch section {
        case .people: Text("People", comment: "Discover section")
        case .packs: Text("Packs", comment: "Discover section")
        case .pictures: Text("Pictures", comment: "Discover section")
        case .videos: Text("Videos", comment: "Discover section")
        case .hashtags: Text("Tags", comment: "Discover section")
        }
    }

    /// The curated subjects; picking one lays out its hashtags underneath,
    /// each of which opens the hashtag's timeline.
    private var categoryChips: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
            ScrollView(.horizontal) {
                HStack(spacing: AlohaMetrics.space2) {
                    ForEach(categories) { category in
                        let isSelected = selectedCategory?.id == category.id
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                selectedCategory = isSelected ? nil : category
                            }
                        } label: {
                            Text(category.name)
                                .font(.footnote.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? palette.onAccent : palette.label)
                                .padding(.horizontal, AlohaMetrics.space3)
                                .frame(minHeight: 34)
                                .background(
                                    isSelected ? palette.accent : palette.surfaceRaised,
                                    in: Capsule()
                                )
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.horizontal, AlohaMetrics.space3)
            }
            .scrollIndicators(.hidden)

            if let selectedCategory, !selectedCategory.hashtags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: AlohaMetrics.space2) {
                        ForEach(selectedCategory.hashtags, id: \.self) { name in
                            NavigationLink(value: Route.hashtag(name)) {
                                Text(verbatim: "#\(name)")
                                    .font(.footnote)
                                    .foregroundStyle(palette.hashtag)
                                    .padding(.horizontal, AlohaMetrics.space3)
                                    .frame(minHeight: 34)
                                    .background(palette.surface, in: Capsule())
                                    .overlay(Capsule().strokeBorder(palette.separator))
                            }
                            .buttonStyle(.plain)
                            .frame(minHeight: 44)
                        }
                    }
                    .padding(.horizontal, AlohaMetrics.space3)
                }
                .scrollIndicators(.hidden)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.bottom, AlohaMetrics.space1)
    }

    // MARK: - People

    private var people: some View {
        List {
            SwiftUI.Section {
                HStack(spacing: AlohaMetrics.space2) {
                    Image(systemName: AlohaSymbol.search)
                        .foregroundStyle(palette.secondaryLabel)
                    TextField(
                        String(
                            localized: "Any name or handle, on any server",
                            comment: "Discover search prompt"),
                        text: $query
                    )
                    .textFieldStyle(.plain)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    #endif
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityLabel(Text("Search people", comment: "Discover search field"))
                    if isSearching {
                        ProgressView().controlSize(.small)
                    } else if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(palette.tertiaryLabel)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Clear search", comment: "Discover search field"))
                    }
                }
                .padding(.horizontal, AlohaMetrics.space3)
                .frame(minHeight: 44)
                .background(
                    palette.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
                )
                .listRowInsets(
                    EdgeInsets(
                        top: AlohaMetrics.space2, leading: AlohaMetrics.space3,
                        bottom: AlohaMetrics.space2, trailing: AlohaMetrics.space3)
                )
                .listRowSeparator(.hidden)
            } footer: {
                if isNextcloud, !directories.isEmpty, query.isEmpty {
                    Text(
                        "Also asks \(directories.map(\.label).formatted(.list(type: .and))).",
                        comment: "Discover search footer naming the directories asked")
                }
            }

            if !query.isEmpty {
                searchResults
            } else {
                if let followGraph, !followGraph.suggestions.isEmpty {
                    SwiftUI.Section {
                        // The same walk, drawn rather than listed. The list
                        // answers "who should I follow"; the constellation
                        // answers "who is around me", which is why the web has
                        // both and why this is a switch rather than a
                        // replacement.
                        if showsConstellation {
                            FollowConstellationView(
                                session: session, suggestions: followGraph.suggestions,
                                onAction: onAction
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(palette.background)
                        }
                        Toggle(isOn: $showsConstellation) {
                            Text("Draw it as a constellation", comment: "Discover section option")
                                .font(.footnote)
                        }
                        ForEach(showsConstellation ? [] : followGraph.suggestions) { suggestion in
                            accountButton(suggestion.account) {
                                if suggestion.count > 0 {
                                    Text(
                                        "^[\(suggestion.count) person](inflect: true) you follow follow them",
                                        comment: "Follow graph row detail"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(palette.tertiaryLabel)
                                }
                            }
                        }
                    } header: {
                        Text("Followed by people you follow", comment: "Discover section")
                    }
                }

                if !suggestions.isEmpty {
                    SwiftUI.Section {
                        ForEach(suggestions) { suggestion in
                            HStack(spacing: 0) {
                                accountButton(suggestion.account) {
                                    if let reason = sourceLabel(suggestion) {
                                        reason
                                            .font(.caption)
                                            .foregroundStyle(palette.tertiaryLabel)
                                    }
                                }
                                Button {
                                    Task { await dismiss(suggestion) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(palette.tertiaryLabel)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    Text("Not interested", comment: "Suggestion action"))
                            }
                        }
                    } header: {
                        Text("People to follow", comment: "Explore section")
                    }
                }

                if !popular.isEmpty {
                    SwiftUI.Section {
                        ForEach(popular) { account in
                            accountButton(account) { EmptyView() }
                        }
                    } header: {
                        Text("Popular here", comment: "Discover section")
                    }
                }

                if !directory.isEmpty {
                    SwiftUI.Section {
                        Picker(selection: $directoryOrder) {
                            Text("Recently active", comment: "Directory order")
                                .tag(Endpoint.search.DirectoryOrder.active)
                            Text("Newest here", comment: "Directory order")
                                .tag(Endpoint.search.DirectoryOrder.new)
                        } label: {
                            Text("Order", comment: "Directory order picker")
                        }
                        .pickerStyle(.segmented)
                        .listRowSeparator(.hidden)

                        ForEach(directory) { account in
                            accountButton(account) { EmptyView() }
                        }
                    } header: {
                        Text("The directory", comment: "Discover section")
                    } footer: {
                        Text(
                            "Everybody on this server who asked to be listed. Nobody appears here without opting in.",
                            comment: "Directory explanation")
                    }
                }

                if !isLoading, followGraph?.suggestions.isEmpty ?? true, suggestions.isEmpty,
                    popular.isEmpty, directory.isEmpty
                {
                    ContentUnavailableView {
                        Text("Nobody to suggest yet", comment: "Empty Discover people")
                    } description: {
                        Text(
                            "Follow a few people and the server will find more like them.",
                            comment: "Empty Discover people detail")
                    }
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        // Unavailable on visionOS, where there is no keyboard over the
        // content to dismiss.
        #if !os(visionOS)
            .scrollDismissesKeyboard(.interactively)
        #endif
    }

    @ViewBuilder
    private var searchResults: some View {
        if !found.isEmpty {
            SwiftUI.Section {
                ForEach(found) { account in
                    accountButton(account) { EmptyView() }
                }
            } header: {
                Text("Found", comment: "Discover search section")
            }
        }

        if isNextcloud, !foundElsewhere.accounts.isEmpty {
            SwiftUI.Section {
                ForEach(foundElsewhere.accounts) { account in
                    accountButton(account) { EmptyView() }
                }
            } header: {
                Text("On other servers", comment: "Discover search section")
            } footer: {
                let answered = foundElsewhere.sources.filter { $0.error == nil }
                if !answered.isEmpty {
                    Text(
                        "From \(answered.map(\.host).formatted(.list(type: .and))).",
                        comment: "Discover search footer naming the servers that answered")
                }
            }
        }

        if !isSearching, found.isEmpty, foundElsewhere.accounts.isEmpty {
            ContentUnavailableView.search(text: query)
                .listRowSeparator(.hidden)
        }
    }

    private func accountButton<Detail: View>(
        _ account: Account, @ViewBuilder detail: () -> Detail
    ) -> some View {
        Button {
            onAction(.openProfile(account))
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                AccountRow(account: account, localHost: session.snapshot.instanceHost)
                detail()
                    .padding(.leading, 40 + AlohaMetrics.space3)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(account.bestDisplayName))
    }

    /// Why the server suggests somebody. Nextcloud Social's own sources say
    /// "colleague"; Mastodon's are staff, past interactions and global.
    private func sourceLabel(_ suggestion: Suggestion) -> Text? {
        let sources = Set((suggestion.sources ?? []) + [suggestion.source].compactMap { $0 })
        if sources.contains(where: { $0.contains("colleague") || $0.contains("nextcloud") }) {
            return Text("Colleague on your Nextcloud", comment: "Suggestion source")
        }
        if sources.contains("featured") || sources.contains("staff") {
            return Text("Featured by your server", comment: "Suggestion source")
        }
        if sources.contains("most_followed") || sources.contains("global") {
            return Text("Widely followed", comment: "Suggestion source")
        }
        if sources.contains("most_interactions") || sources.contains("past_interactions") {
            return Text("You've interacted before", comment: "Suggestion source")
        }
        if sources.contains("similar_to_recently_followed") {
            return Text("Like people you recently followed", comment: "Suggestion source")
        }
        return nil
    }

    // MARK: - Hashtags

    private var hashtags: some View {
        List {
            if !trendingTags.isEmpty {
                SwiftUI.Section {
                    ForEach(trendingTags) { tag in tagRow(tag) }
                } header: {
                    HStack {
                        Text("Trending hashtags", comment: "Explore section")
                        Spacer()
                        // Only Nextcloud Social narrows trends by period;
                        // Mastodon ignores the parameter, and a control that
                        // changes nothing is worse than no control.
                        if isNextcloud {
                            Picker(selection: $period) {
                                Text("Hour", comment: "Trend period").tag("1h")
                                Text("Today", comment: "Trend period").tag("1d")
                                Text("3 days", comment: "Trend period").tag("3d")
                                Text("10 days", comment: "Trend period").tag("10d")
                            } label: {
                                Text("Period", comment: "Trend period picker")
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .accessibilityLabel(
                                Text("Trend period", comment: "Trend period picker"))
                        }
                    }
                }
            }

            if !elsewhereTags.isEmpty {
                SwiftUI.Section {
                    ForEach(elsewhereTags) { tag in tagRow(tag) }
                } header: {
                    Text("On other servers", comment: "Discover section")
                }
            }

            if !trendingLinks.isEmpty {
                SwiftUI.Section {
                    ForEach(Array(trendingLinks.enumerated()), id: \.offset) { _, card in
                        LinkCardView(card: card) { onAction(.openCard(card)) }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                } header: {
                    Text("Trending links", comment: "Explore section")
                }
            }

            if !isLoading && trendingTags.isEmpty && elsewhereTags.isEmpty && trendingLinks.isEmpty
            {
                ContentUnavailableView {
                    Text("Nothing trending", comment: "Empty Explore")
                } description: {
                    Text(
                        "Your server hasn't seen enough activity to rank anything yet.",
                        comment: "Empty Explore detail")
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    private func tagRow(_ tag: Tag) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            NavigationLink(value: Route.hashtag(tag.name)) {
                HashtagRow(tag: tag)
            }
            HashtagFollowButton(
                isFollowing: followedTags.contains(tag.id),
                name: tag.name
            ) { await toggleFollow(tag) }
        }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let categoriesTask: Void = loadCategories()
        async let peopleTask: Void = loadPeople()
        async let tagsTask: Void = loadTrendingTags()
        async let restTask: Void = loadTagExtras()
        _ = await (categoriesTask, peopleTask, tagsTask, restTask)
    }

    private func loadCategories() async {
        guard isNextcloud else { return }
        categories =
            (try? await session.client.decode(
                DiscoverCategories.self, from: Endpoint.discovery.categories))?.categories ?? []
    }

    private func loadPeople() async {
        suggestions =
            (try? await session.client.decode(
                LossyArray<Suggestion>.self, from: Endpoint.search.suggestions))?.elements ?? []
        guard isNextcloud else { return }
        directories =
            (try? await session.client.decode(
                LossyArray<DirectorySource>.self, from: Endpoint.discovery.directories))?.elements
            ?? []
        popular =
            (try? await session.client.decode(
                LossyArray<Account>.self, from: Endpoint.discovery.popularAccounts()))?.elements
            ?? []
        // The walk asks other servers, so it is only made when the server says
        // there are enough follows for it to be worth the requests.
        let status = try? await session.client.decode(
            FollowGraphStatus.self, from: Endpoint.discovery.followGraphStatus)
        if status?.isWorthwhile ?? true {
            followGraph = try? await session.client.decode(
                FollowGraph.self, from: Endpoint.discovery.followGraph)
        }
    }

    /// The instance's own directory. Public, so it loads signed out too, and
    /// separately from `load()` so changing the order is one request rather
    /// than a whole refresh.
    private func loadDirectory() async {
        directory =
            (try? await session.client.decode(
                LossyArray<Account>.self,
                from: Endpoint.search.directory(order: directoryOrder)))?.elements ?? []
    }

    private func loadTrendingTags() async {
        // Nextcloud Social accepts 1h, 12h, 1d, 3d and 10d; anything else falls
        // back to the default rather than failing.
        trendingTags =
            (try? await session.client.decode(
                LossyArray<Tag>.self,
                from: Endpoint.search.trendingTags(limit: 20, period: period)))?.elements ?? []
    }

    private func loadTagExtras() async {
        trendingLinks =
            (try? await session.client.decode(
                LossyArray<Card>.self, from: Endpoint.search.trendingLinks(limit: 10)))?.elements
            ?? []
        followedTags = Set(
            ((try? await session.client.decode(
                LossyArray<Tag>.self, from: Endpoint.tags.followed(limit: 50)))?.elements ?? [])
                .map(\.id))
        guard isNextcloud else { return }
        elsewhereTags =
            (try? await session.client.decode(
                DirectoryHashtagResults.self, from: Endpoint.discovery.directoryHashtags()))?
            .hashtags ?? []
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            found = []
            foundElsewhere = DirectorySearchResults()
            return
        }
        // Wait for typing to settle before every keystroke becomes a request.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }

        async let local = session.client.decode(
            SearchResults.self,
            from: Endpoint.search.search(trimmed, type: "accounts", resolve: true, limit: 20))
        async let elsewhere: DirectorySearchResults? =
            isNextcloud
            ? try? await session.client.decode(
                DirectorySearchResults.self, from: Endpoint.discovery.directorySearch(trimmed))
            : nil
        let localResults = try? await local
        let elsewhereResults = await elsewhere
        guard !Task.isCancelled else { return }
        found = localResults?.accounts ?? []
        // Somebody found locally need not appear again from a directory.
        let seen = Set(found.map { $0.acct.lowercased() })
        var remote = elsewhereResults ?? DirectorySearchResults()
        remote.accounts.removeAll { seen.contains($0.acct.lowercased()) }
        foundElsewhere = remote
    }

    private func dismiss(_ suggestion: Suggestion) async {
        suggestions.removeAll { $0.id == suggestion.id }
        _ = try? await session.client.send(
            Endpoint.search.dismissSuggestion(suggestion.account.id))
    }

    private func toggleFollow(_ tag: Tag) async {
        let wasFollowing = followedTags.contains(tag.id)
        if wasFollowing { followedTags.remove(tag.id) } else { followedTags.insert(tag.id) }
        do {
            let updated = try await session.client.decode(
                Tag.self,
                from: wasFollowing
                    ? Endpoint.tags.unfollow(tag.name) : Endpoint.tags.follow(tag.name))
            if updated.following == true {
                followedTags.insert(tag.id)
            } else if updated.following == false {
                followedTags.remove(tag.id)
            }
        } catch {
            if wasFollowing { followedTags.insert(tag.id) } else { followedTags.remove(tag.id) }
            await session.handle(error)
        }
    }
}

/// Follow or unfollow a hashtag from wherever it is listed.
struct HashtagFollowButton: View {
    @Environment(\.alohaPalette) private var palette

    let isFollowing: Bool
    let name: String
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: isFollowing ? "checkmark" : "plus")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isFollowing ? palette.onAccent : palette.accent)
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(isFollowing ? palette.accent : palette.accent.opacity(0.12))
                        .padding(6)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isFollowing
                ? Text("Unfollow #\(name)", comment: "Hashtag follow button")
                : Text("Follow #\(name)", comment: "Hashtag follow button")
        )
        .accessibilityAddTraits(isFollowing ? [.isButton, .isSelected] : .isButton)
    }
}
