// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

// Discovering through Bluesky, where the server reads Bluesky for this
// account: who Bluesky suggests, what is trending there, and its starter
// packs. A Bluesky account is a handle and a DID until this server has looked
// it up, so opening one goes through the account search, which is what makes
// it an account here that can be followed.

/// Somebody on Bluesky, drawn the way an `AccountRow` draws a person.
struct BlueskyPersonRow: View {
    @Environment(\.alohaPalette) private var palette

    let person: BlueskyPerson

    var body: some View {
        HStack(spacing: AlohaMetrics.space3) {
            RemoteImage(url: person.avatar) {
                Circle().fill(Monogram.colour(for: person.handle, lightness: 0.46))
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.displayName)
                    .font(AlohaType.name)
                    .lineLimit(1)
                Text(verbatim: "@\(person.handle)")
                    .font(AlohaType.meta)
                    .foregroundStyle(palette.tertiaryLabel)
                    .lineLimit(1)
                if !person.note.isEmpty {
                    Text(person.note)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Turns a Bluesky handle into an account on this server — the account
/// search with `resolve`, which asks Bluesky — so it opens as any profile.
enum BlueskyLookup {
    static func account(for handle: String, session: AccountSession) async throws -> Account? {
        try await session.client.decode(
            SearchResults.self,
            from: Endpoint.search.search(handle, type: "accounts", resolve: true, limit: 1)
        ).accounts.first
    }
}

/// Who Bluesky suggests, as a section of Discover's people.
struct BlueskySuggestionsSection: View {
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession
    let onAction: (StatusRowAction) -> Void

    @State private var people: [BlueskyPerson] = []
    @State private var opening: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if !people.isEmpty {
                Section {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(palette.destructive)
                    }
                    ForEach(people.prefix(10)) { person in
                        Button {
                            Task { await open(person) }
                        } label: {
                            HStack {
                                BlueskyPersonRow(person: person)
                                if opening == person.id { ProgressView() }
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(opening != nil)
                        .accessibilityLabel(Text(person.displayName))
                    }
                } header: {
                    Text("Suggested on Bluesky", comment: "Discover section")
                }
            }
        }
        .task(id: session.id) { await load() }
    }

    private func load() async {
        people =
            (try? await session.client.decode(
                BlueskySuggestionList.self, from: Endpoint.bluesky.suggestions))?.accounts ?? []
    }

    private func open(_ person: BlueskyPerson) async {
        guard opening == nil else { return }
        opening = person.id
        defer { opening = nil }
        do {
            if let account = try await BlueskyLookup.account(for: person.handle, session: session) {
                errorMessage = nil
                onAction(.openProfile(account))
            } else {
                errorMessage = String(
                    localized: "That account couldn't be found from here.",
                    comment: "Bluesky suggestion lookup found nobody")
            }
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}

/// What is trending on Bluesky: each a feed to read here, or a search.
struct BlueskyTrendsSection: View {
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession

    @State private var trends: [BlueskyTrend] = []

    var body: some View {
        Group {
            if !trends.isEmpty {
                Section {
                    ForEach(trends.prefix(12)) { trend in
                        NavigationLink(value: route(for: trend)) {
                            Label {
                                Text(trend.title)
                            } icon: {
                                Image(
                                    systemName: trend.feed.isEmpty
                                        ? "magnifyingglass" : "dot.radiowaves.up.forward")
                            }
                        }
                    }
                } header: {
                    Text("Trending on Bluesky", comment: "Discover section")
                }
            }
        }
        .task(id: session.id) {
            trends =
                (try? await session.client.decode(
                    BlueskyTrendList.self, from: Endpoint.bluesky.trends))?.trends ?? []
        }
    }

    private func route(for trend: BlueskyTrend) -> Route {
        trend.feed.isEmpty
            ? .search(query: trend.search.isEmpty ? trend.topic : trend.search)
            : .blueskyFeed(uri: trend.feed, name: trend.title)
    }
}

/// Opening a Bluesky starter pack by its link, from the Packs tab.
struct BlueskyStarterPackLinkRow: View {
    @State private var address = ""

    private var trimmed: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A bsky.app starter pack address or an `at://` URI; the server reads
    /// either and says when it is neither.
    private var looksLikePack: Bool {
        trimmed.hasPrefix("at://") || trimmed.contains("bsky.app/starter-pack")
            || trimmed.contains("go.bsky.app/")
    }

    var body: some View {
        HStack(spacing: AlohaMetrics.space2) {
            TextField(
                String(
                    localized: "Link to a Bluesky starter pack",
                    comment: "Bluesky starter pack link field"),
                text: $address
            )
            #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            #endif
            .autocorrectionDisabled()
            NavigationLink(value: Route.blueskyStarterPack(address: trimmed)) {
                Text("Open", comment: "Bluesky starter pack link action")
                    .font(.footnote.weight(.semibold))
            }
            .disabled(!looksLikePack)
        }
    }
}

/// One Bluesky starter pack: who made it, who is in it, the feeds that come
/// with it, and a button that follows everyone not followed yet.
struct BlueskyStarterPackView: View {
    @Environment(\.alohaPalette) private var palette

    let address: String
    let session: AccountSession

    @State private var pack: BlueskyStarterPack?
    @State private var followed: Set<String> = []
    @State private var failed: Set<String> = []
    @State private var keepFeeds = true
    @State private var isLoading = true
    @State private var isFollowing = false
    @State private var errorMessage: String?

    private var toFollow: [BlueskyPerson] {
        pack?.members.filter { !$0.following && !followed.contains($0.did) } ?? []
    }

    var body: some View {
        List {
            if let errorMessage {
                AlohaErrorStrip(message: errorMessage) {
                    Task { pack == nil ? await load() : await followAll() }
                }
                .listRowSeparator(.hidden)
            }

            if let pack {
                Section {
                    VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                        if let creator = pack.creator {
                            Text(
                                "By \(creator.displayName) · @\(creator.handle)",
                                comment: "Bluesky starter pack creator"
                            )
                            .font(AlohaType.meta)
                            .foregroundStyle(palette.secondaryLabel)
                        }
                        if !pack.description.isEmpty {
                            Text(pack.description)
                                .font(.body)
                                .foregroundStyle(palette.secondaryLabel)
                        }
                        if pack.joined > 0 {
                            Text(
                                "^[\(pack.joined) person](inflect: true) joined Bluesky with it",
                                comment: "Bluesky starter pack joined count"
                            )
                            .font(AlohaType.meta)
                            .foregroundStyle(palette.tertiaryLabel)
                        }
                        if !pack.feeds.isEmpty {
                            Toggle(isOn: $keepFeeds) {
                                Text(
                                    "Keep its ^[\(pack.feeds.count) feed](inflect: true) too",
                                    comment: "Bluesky starter pack keep feeds switch")
                            }
                        }
                        followAllButton
                    }
                    .padding(.vertical, AlohaMetrics.space1)
                }

                Section {
                    ForEach(pack.members) { member in
                        HStack {
                            BlueskyPersonRow(person: member)
                            if member.following || followed.contains(member.did) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(palette.accent)
                                    .accessibilityLabel(
                                        Text("Following", comment: "Starter pack member state"))
                            } else if failed.contains(member.did) {
                                Image(systemName: AlohaSymbol.warning)
                                    .foregroundStyle(palette.destructive)
                                    .accessibilityLabel(
                                        Text(
                                            "Couldn't be followed",
                                            comment: "Starter pack member state"))
                            }
                        }
                    }
                } header: {
                    Text(
                        "^[\(pack.members.count) account](inflect: true)",
                        comment: "Starter pack section")
                }

                if !pack.feeds.isEmpty {
                    Section {
                        ForEach(pack.feeds) { feed in
                            NavigationLink(
                                value: Route.blueskyFeed(uri: feed.uri, name: feed.title)
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feed.title)
                                    if !feed.description.isEmpty {
                                        Text(feed.description)
                                            .font(.footnote)
                                            .foregroundStyle(palette.secondaryLabel)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Feeds", comment: "Bluesky starter pack section")
                    }
                }
            } else if isLoading {
                SkeletonListRow(person: 5)
            }
        }
        .navigationTitle(
            pack.map { Text($0.name) }
                ?? Text("Starter pack", comment: "Screen title")
        )
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let url = pack?.url {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var followAllButton: some View {
        Button {
            Task { await followAll() }
        } label: {
            HStack(spacing: AlohaMetrics.space2) {
                if isFollowing {
                    ProgressView().controlSize(.small)
                    Text("Following everyone…", comment: "Starter pack action in progress")
                } else if toFollow.isEmpty {
                    Image(systemName: "checkmark")
                    Text("You follow everyone in it", comment: "Starter pack all followed")
                } else {
                    Image(systemName: "person.3.sequence.fill")
                    Text(
                        "Follow ^[\(toFollow.count) account](inflect: true)",
                        comment: "Starter pack follow all action")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .alohaGlassProminentButtonStyle()
        .disabled(isFollowing || toFollow.isEmpty)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            pack = try await session.client.decode(
                BlueskyStarterPackEnvelope.self, from: Endpoint.bluesky.starterPack(address)
            ).pack
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "The starter pack could not be opened.",
                    comment: "Bluesky starter pack load failure")
        }
    }

    /// A batch at a time, as many as the server follows in one request; the
    /// feeds are kept with the first batch only.
    private func followAll() async {
        guard let pack, !isFollowing else { return }
        isFollowing = true
        defer { isFollowing = false }
        errorMessage = nil
        let dids = toFollow.map(\.did)
        let batches = stride(from: 0, to: dids.count, by: Endpoint.bluesky.starterPackFollowBatch)
            .map { Array(dids[$0..<min($0 + Endpoint.bluesky.starterPackFollowBatch, dids.count)]) }
        for (index, batch) in batches.enumerated() {
            do {
                let result = try await session.client.decode(
                    BlueskyStarterPackFollowResult.self,
                    from: Endpoint.bluesky.followStarterPack(
                        pack.uri, dids: batch, keepFeeds: keepFeeds && index == 0))
                followed.formUnion(result.followed)
                failed.formUnion(result.failed)
            } catch {
                await session.handle(error)
                errorMessage =
                    (error as? APIError)?.errorDescription
                    ?? String(
                        localized: "Not everyone could be followed. Please try again.",
                        comment: "Bluesky starter pack follow failure")
                return
            }
        }
    }
}
