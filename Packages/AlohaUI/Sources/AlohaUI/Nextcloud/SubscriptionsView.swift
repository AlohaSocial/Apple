// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI
import UniformTypeIdentifiers

/// Feeds outside the fediverse — RSS, Atom, YouTube channels — that the server
/// reads for you. Every entry links back to where it came from; nothing is
/// copied, which is why this is a list of links and not a timeline of posts.
public struct SubscriptionsView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.openURL) private var openURL

    private let session: AccountSession

    @State private var feeds: [SubscriptionFeed] = []
    @State private var entries: [SubscriptionEntry] = []
    @State private var newURL = ""
    @State private var isFollowing = false
    @State private var isLoadingFeeds = true
    @State private var isLoadingEntries = false
    @State private var entriesRequestID = UUID()
    @State private var mayHaveMore = true
    @State private var isImporting = false
    @State private var importedCount: Int?
    @State private var errorMessage: String?
    @State private var entriesError: String?

    private static let pageSize = 40

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        List {
            Section {
                Text(
                    "Follow a feed or a YouTube channel here and its latest entries appear below, linked to where they live. Nothing is copied to your server.",
                    comment: "Subscriptions explanation"
                )
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)
                .listRowBackground(palette.background)
                .listRowSeparator(.hidden)
            }

            addSection
            takeoutSection
            feedsSection
            entriesSection
        }
        .alohaGround(palette)
        .navigationTitle(Text("Subscriptions", comment: "Screen title"))
        .refreshable {
            await loadFeeds()
            await loadEntries(reset: true)
        }
        .task {
            await loadFeeds()
            await loadEntries(reset: true)
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.commaSeparatedText, .plainText, .data]
        ) { result in
            guard case .success(let url) = result else { return }
            Task { await importTakeout(from: url) }
        }
    }

    // MARK: - Sections

    private var addSection: some View {
        Section {
            HStack(spacing: AlohaMetrics.space2) {
                TextField(
                    String(
                        localized: "Feed or channel address", comment: "Subscriptions add prompt"),
                    text: $newURL
                )
                .textFieldStyle(.plain)
                #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .onSubmit { Task { await follow() } }
                .accessibilityLabel(Text("Feed address", comment: "Subscriptions add field label"))

                Button {
                    Task { await follow() }
                } label: {
                    if isFollowing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Follow", comment: "Subscriptions add action")
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.regular)
                .disabled(!canFollow || isFollowing)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(palette.destructive)
            }
        } header: {
            Text("Follow a feed", comment: "Subscriptions section")
        }
    }

    private var takeoutSection: some View {
        Section {
            DisclosureGroup {
                Text(
                    "In Google Takeout, export YouTube and YouTube Music with only Subscriptions selected. The archive holds a subscriptions.csv; choose it here and every channel in it is followed.",
                    comment: "Takeout import explanation"
                )
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)

                Button {
                    isImporting = true
                } label: {
                    Label {
                        Text("Choose subscriptions.csv", comment: "Takeout import action")
                    } icon: {
                        Image(systemName: "doc.badge.arrow.up")
                    }
                }

                if let importedCount {
                    Text(
                        "^[\(importedCount) channel](inflect: true) newly followed.",
                        comment: "Takeout import result"
                    )
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                }
            } label: {
                Label {
                    Text("Bring my YouTube subscriptions", comment: "Takeout import disclosure")
                } icon: {
                    Image(systemName: "play.rectangle")
                }
            }
        }
    }

    private var feedsSection: some View {
        Section {
            ForEach(feeds) { feed in
                feedRow(feed)
            }
            .onDelete { offsets in
                // The rows are read off the array here, where the indexes
                // still mean what they say: the request runs later, and a
                // reload can move everything underneath it by then.
                let targets = offsets.compactMap { feeds.indices.contains($0) ? feeds[$0] : nil }
                let previous = feeds
                let ids = Set(targets.map(\.id))
                feeds.removeAll { ids.contains($0.id) }
                Task { await unfollow(targets, restoring: previous) }
            }

            if isLoadingFeeds && feeds.isEmpty {
                SkeletonListRow(person: 5)
                    .listRowBackground(palette.background)
                    .listRowSeparator(.hidden)
            } else if feeds.isEmpty && errorMessage == nil {
                Text("You follow no feeds yet.", comment: "Empty subscriptions")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
            }
        } header: {
            Text("Followed feeds", comment: "Subscriptions section")
        }
    }

    private func feedRow(_ feed: SubscriptionFeed) -> some View {
        HStack(alignment: .top, spacing: AlohaMetrics.space3) {
            Image(systemName: "dot.radiowaves.up.forward")
                .foregroundStyle(palette.accent)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                if let site = feed.siteURL ?? feed.url {
                    Link(destination: site) {
                        Text(feed.displayTitle)
                            .font(AlohaType.name)
                            .foregroundStyle(palette.label)
                    }
                } else {
                    Text(feed.displayTitle).font(AlohaType.name)
                }

                if let error = feed.error {
                    Text(error)
                        .font(AlohaType.meta)
                        .foregroundStyle(palette.destructive)
                } else if feed.lastReadAt == nil {
                    Text("Not read yet", comment: "Subscription feed state")
                        .font(AlohaType.meta)
                        .foregroundStyle(palette.tertiaryLabel)
                } else if feed.entryCount == 0 {
                    Text("Read fine, but it lists nothing", comment: "Subscription feed state")
                        .font(AlohaType.meta)
                        .foregroundStyle(palette.tertiaryLabel)
                } else {
                    Text(
                        "^[\(feed.entryCount) entry](inflect: true)",
                        comment: "Subscription feed count"
                    )
                    .font(AlohaType.meta)
                    .foregroundStyle(palette.tertiaryLabel)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }

    private var entriesSection: some View {
        Section {
            ForEach(entries) { entry in
                entryRow(entry)
            }

            if let entriesError {
                VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                    Text(entriesError)
                        .font(.footnote)
                        .foregroundStyle(palette.destructive)
                    Button {
                        Task { await loadEntries(reset: entries.isEmpty) }
                    } label: {
                        Text("Try again", comment: "Subscriptions retry action")
                    }
                    .controlSize(.small)
                }
            } else if entries.isEmpty && !isLoadingEntries {
                Text(
                    "Nothing yet. Entries appear once a feed you follow has been read.",
                    comment: "Empty subscription entries"
                )
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)
            }

            if isLoadingEntries {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if mayHaveMore && !entries.isEmpty {
                Button {
                    Task { await loadEntries(reset: false) }
                } label: {
                    Text("Older", comment: "Subscriptions paging action")
                        .frame(maxWidth: .infinity)
                }
            }
        } header: {
            Text("Latest entries", comment: "Subscriptions section")
        }
    }

    private func entryRow(_ entry: SubscriptionEntry) -> some View {
        Button {
            if let url = entry.url { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
                Text(entry.title.isEmpty ? (entry.url?.absoluteString ?? "") : entry.title)
                    .font(AlohaType.name)
                    .foregroundStyle(palette.label)
                    .multilineTextAlignment(.leading)

                HStack(spacing: AlohaMetrics.space1) {
                    if let feedTitle = entry.feedTitle, !feedTitle.isEmpty {
                        Text(feedTitle)
                    }
                    if let date = entry.publishedAt {
                        if entry.feedTitle?.isEmpty == false { Text(verbatim: "·") }
                        Text(PostAge.short(date))
                    }
                }
                .font(AlohaType.meta)
                .foregroundStyle(palette.tertiaryLabel)

                if let summary = entry.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !summary.isEmpty
                {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryLabel)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(entry.url == nil)
        .accessibilityHint(Text("Opens in the browser", comment: "Subscription entry hint"))
    }

    // MARK: - Actions

    private var canFollow: Bool {
        let trimmed = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains(".") && !trimmed.contains(" ")
    }

    private func follow() async {
        let submittedURL = newURL
        let address = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canFollow, !isFollowing else { return }
        isFollowing = true
        defer { isFollowing = false }
        do {
            _ = try await session.client.send(Endpoint.subscriptions.follow(url: address))
            if newURL == submittedURL { newURL = "" }
            errorMessage = nil
            await loadFeeds()
            await loadEntries(reset: true)
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "That could not be followed.", comment: "Subscriptions follow failed"
                )
        }
    }

    /// The rows are already gone from the screen; a refusal puts them back
    /// rather than leaving a follow that silently survived.
    private func unfollow(
        _ targets: [SubscriptionFeed], restoring previous: [SubscriptionFeed]
    )
        async
    {
        var refused = false
        for feed in targets {
            do {
                _ = try await session.client.send(Endpoint.subscriptions.unfollow(feed.id))
            } catch {
                refused = true
                feeds = Self.restoring(feed, in: feeds, previous: previous)
                await session.handle(error)
            }
        }
        if refused {
            errorMessage = String(
                localized: "That feed could not be unfollowed.",
                comment: "Subscriptions unfollow failed")
        }
    }

    private func importTakeout(from url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = String(
                localized: "That file could not be read.", comment: "Takeout import failed")
            return
        }
        do {
            let result = try await session.client.decode(
                TakeoutResult.self,
                from: Endpoint.subscriptions.importTakeout(
                    csv: data, filename: url.lastPathComponent))
            importedCount = result.subscribed
            errorMessage = nil
            await loadFeeds()
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    /// Roll back only a refused removal, never the complete pre-request
    /// snapshot: other removals may have succeeded and new feeds may exist.
    nonisolated static func restoring(
        _ feed: SubscriptionFeed, in current: [SubscriptionFeed], previous: [SubscriptionFeed]
    ) -> [SubscriptionFeed] {
        guard !current.contains(where: { $0.id == feed.id }) else { return current }
        var restored = current
        let index = previous.firstIndex(where: { $0.id == feed.id }) ?? restored.count
        restored.insert(feed, at: min(index, restored.count))
        return restored
    }

    private func loadFeeds() async {
        isLoadingFeeds = true
        defer { isLoadingFeeds = false }
        do {
            let response = try await session.client.decode(
                FeedsPage.self, from: Endpoint.subscriptions.feeds
            ).feeds
            guard !Task.isCancelled else { return }
            feeds = response
            errorMessage = nil
        } catch {
            // A server that will not answer is an error, not an empty list.
            guard !Task.isCancelled else { return }
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "Couldn't load your feeds.", comment: "Subscriptions feeds failed")
        }
    }

    private func loadEntries(reset: Bool) async {
        guard reset || !isLoadingEntries else { return }
        let requestID = UUID()
        entriesRequestID = requestID
        isLoadingEntries = true
        defer { if entriesRequestID == requestID { isLoadingEntries = false } }
        do {
            let maxID = reset ? nil : entries.last?.id
            let page = try await session.client.decode(
                EntriesPage.self,
                from: Endpoint.subscriptions.timeline(limit: Self.pageSize, maxID: maxID))
            guard !Task.isCancelled, entriesRequestID == requestID else { return }
            if reset {
                entries = page.items
            } else {
                let known = Set(entries.map(\.id))
                entries += page.items.filter { !known.contains($0.id) }
            }
            mayHaveMore = page.items.count >= Self.pageSize
            entriesError = nil
        } catch {
            guard !Task.isCancelled, entriesRequestID == requestID else { return }
            await session.handle(error)
            guard entriesRequestID == requestID else { return }
            entriesError =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "Couldn't load entries.", comment: "Subscriptions entries failed")
        }
    }

    // The three envelope shapes the routes answer with.
    private struct FeedsPage: Decodable {
        var feeds: [SubscriptionFeed]
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            feeds =
                (try? c.decode(LossyArray<SubscriptionFeed>.self, forKey: .feeds))?.elements ?? []
        }
        enum CodingKeys: String, CodingKey { case feeds }
    }

    private struct EntriesPage: Decodable {
        var items: [SubscriptionEntry]
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            items =
                (try? c.decode(LossyArray<SubscriptionEntry>.self, forKey: .items))?.elements ?? []
        }
        enum CodingKeys: String, CodingKey { case items }
    }

    private struct TakeoutResult: Decodable {
        @LenientInt var subscribed: Int
    }
}
