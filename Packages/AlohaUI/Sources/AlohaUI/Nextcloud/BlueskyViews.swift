// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

// Aloha Social reads Bluesky for the reader: the feeds and lists they keep
// there arrive as ordinary statuses, and their own account is published there
// under a handle the server gives them. These are the two screens for it. The
// rest of Bluesky's settings — moving an account, recovery phrases, labelers,
// Bluesky app passwords — stay in the web interface, where they are set up
// once and several of them need a password confirmation.

/// The Bluesky feeds and lists the reader keeps, each one a timeline.
public struct BlueskyFeedsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession

    @State private var feeds: [BlueskyFeed] = []
    @State private var suggested: [BlueskyFeed] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var newFeed = ""
    @State private var isAdding = false

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        List {
            if let errorMessage {
                AlohaErrorStrip(message: errorMessage) {
                    Task { await load() }
                }
                .listRowBackground(palette.background)
            }

            Section {
                ForEach(feeds) { feed in
                    NavigationLink(value: Route.blueskyFeed(uri: feed.uri, name: feed.title)) {
                        feedLabel(feed)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await remove(feed) }
                        } label: {
                            Text("Remove", comment: "Remove a Bluesky feed")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await remove(feed) }
                        } label: {
                            Label {
                                Text("Remove", comment: "Remove a Bluesky feed")
                            } icon: {
                                Image(systemName: AlohaSymbol.delete)
                            }
                        }
                    }
                }
                if feeds.isEmpty && !isLoading && errorMessage == nil {
                    Text(
                        "You don't keep any Bluesky feeds yet. Add one below, or pick a suggestion.",
                        comment: "Empty Bluesky feeds"
                    )
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                }
            } header: {
                Text("Your feeds", comment: "Bluesky feeds section")
            }

            Section {
                TextField(
                    text: $newFeed,
                    prompt: Text(
                        "bsky.app/profile/…/feed/…", comment: "Bluesky feed address placeholder")
                ) {
                    Text("Feed address", comment: "Bluesky feed address field")
                }
                .textContentType(.URL)
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                #endif
                .onSubmit { Task { await add(newFeed) } }

                Button {
                    Task { await add(newFeed) }
                } label: {
                    Text("Add feed", comment: "Bluesky feeds action")
                }
                .disabled(
                    newFeed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAdding)
            } header: {
                Text("Add a feed", comment: "Bluesky feeds section")
            } footer: {
                Text(
                    "Paste a feed's or a list's bsky.app address, or its at:// address.",
                    comment: "Bluesky add feed explanation")
            }

            let unkept = suggested.filter { candidate in
                !feeds.contains { $0.uri == candidate.uri }
            }
            if !unkept.isEmpty {
                Section {
                    ForEach(unkept) { feed in
                        HStack {
                            feedLabel(feed)
                            Spacer(minLength: AlohaMetrics.space2)
                            Button {
                                Task { await add(feed.uri) }
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(
                                Text("Add \(feed.title)", comment: "Add a suggested Bluesky feed")
                            )
                            .disabled(isAdding)
                        }
                    }
                } header: {
                    Text("Suggested by Bluesky", comment: "Bluesky feeds section")
                }
            }
        }
        .alohaGround(palette)
        .navigationTitle(Text("Bluesky feeds", comment: "Screen title"))
        .overlay {
            if isLoading && feeds.isEmpty { SkeletonListRow(text: 4) }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func feedLabel(_ feed: BlueskyFeed) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                    .lineLimit(1)
                if !feed.creator.isEmpty {
                    Text(
                        feed.kind == .list
                            ? "List by @\(feed.creator)" : "Feed by @\(feed.creator)",
                        comment: "Bluesky feed byline"
                    )
                    .font(AlohaType.meta)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
                }
                if !feed.description.isEmpty {
                    Text(feed.description)
                        .font(AlohaType.meta)
                        .foregroundStyle(palette.tertiaryLabel)
                        .lineLimit(2)
                }
            }
        } icon: {
            Image(systemName: feed.kind == .list ? AlohaSymbol.list : "dot.radiowaves.up.forward")
                .foregroundStyle(palette.accent)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let kept = session.client.decode(BlueskyFeedList.self, from: .bluesky.feeds)
            async let offered = try? session.client.decode(
                BlueskyFeedList.self, from: .bluesky.suggestedFeeds)
            feeds = try await kept.feeds
            suggested = await offered?.feeds ?? []
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func add(_ address: String) async {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isAdding = true
        defer { isAdding = false }
        do {
            let added = try await session.client.decode(
                BlueskyFeedEnvelope.self, from: .bluesky.addFeed(trimmed)
            ).feed
            feeds.removeAll { $0.uri == added.uri }
            feeds.insert(added, at: 0)
            newFeed = ""
            errorMessage = nil
        } catch {
            await session.handle(error)
            // A 422 says what was wrong with the address, in words for people.
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func remove(_ feed: BlueskyFeed) async {
        let before = feeds
        feeds.removeAll { $0.uri == feed.uri }
        do {
            try await session.client.send(.bluesky.removeFeed(uri: feed.uri))
        } catch {
            feeds = before
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// One kept Bluesky feed, read as a timeline.
struct BlueskyFeedTimelineView: View {
    let uri: String
    let name: String
    let session: AccountSession
    let onAction: (StatusRowAction) -> Void

    var body: some View {
        TimelineView(
            key: TimelineKey(mode: .home, source: .bluesky(feedURI: uri)),
            session: session, onAction: onAction
        )
        .navigationTitle(name)
    }
}

/// The reader's own account on Bluesky: the handle it is published under,
/// whether it is there at all, and whether their blocks are published.
public struct BlueskySettingsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession

    @State private var identity: BlueskyIdentity?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var hasNoIdentity = false
    @State private var handleDraft = ""
    @State private var followFromDraft = ""
    @State private var isQueueingFollows = false
    /// Bumped when follows are queued, so the imports below read again.
    @State private var importsReload = 0

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        Form {
            if let errorMessage {
                AlohaErrorStrip(message: errorMessage) {
                    Task { await load() }
                }
            }

            if let identity {
                Section {
                    LabeledContent {
                        Text(verbatim: "@\(identity.handle)")
                            .textSelection(.enabled)
                    } label: {
                        Text("Handle", comment: "Bluesky identity row")
                    }
                    if identity.customHandleBroken, !identity.customHandle.isEmpty {
                        Label {
                            Text(
                                "Your own domain, \(identity.customHandle), no longer points here, so Bluesky shows @\(identity.assignedHandle) instead.",
                                comment: "Bluesky custom handle is broken")
                        } icon: {
                            Image(systemName: AlohaSymbol.warning)
                        }
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryLabel)
                    }
                    if let url = identity.url {
                        Link(destination: url) {
                            Text("See your profile on Bluesky", comment: "Bluesky identity action")
                        }
                    }
                } header: {
                    Text("Your account on Bluesky", comment: "Bluesky settings section")
                } footer: {
                    Text(
                        "People on Bluesky can follow you and reply to you here. Your posts are published there as they are here.",
                        comment: "Bluesky identity explanation")
                }

                Section {
                    Toggle(
                        isOn: Binding(
                            get: { identity.active },
                            set: { value in Task { await setActive(value) } })
                    ) {
                        Text("Be on Bluesky", comment: "Bluesky presence switch")
                    }
                    .disabled(isSaving)

                    Toggle(
                        isOn: Binding(
                            get: { identity.publishBlocks ?? false },
                            set: { value in Task { await setPublishBlocks(value) } })
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Publish my blocks", comment: "Bluesky publish blocks switch")
                            Text(
                                "On Bluesky a block is public. Off, the accounts you block there are blocked here only.",
                                comment: "Bluesky publish blocks explanation"
                            )
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryLabel)
                        }
                    }
                    .disabled(isSaving || !identity.active)
                } footer: {
                    Text(
                        "Switching off signs every Bluesky app out of your account there. Your handle stays yours, and switching on again brings it back as it was.",
                        comment: "Bluesky presence explanation")
                }

                ownDomainSection(identity)
            } else if hasNoIdentity {
                Section {
                    Text(
                        "Your account isn't published on Bluesky. Your server's web interface can set that up.",
                        comment: "No Bluesky identity"
                    )
                    .foregroundStyle(palette.secondaryLabel)
                }
            }

            Section {
                NavigationLink(value: Route.blueskyFeeds) {
                    Text("Bluesky feeds", comment: "Settings item")
                }
            }

            followFromSection
            MigrationImportsSection(
                session: session, kinds: ["bluesky_follows"], reload: importsReload)
        }
        .alohaGround(palette)
        .navigationTitle(Text("Bluesky", comment: "Screen title"))
        .overlay {
            if isLoading && identity == nil { SkeletonListRow(text: 3) }
        }
        .task { await load() }
    }

    /// A handle on a domain the reader owns, once the domain names their DID
    /// — `_atproto` TXT record or `/.well-known/atproto-did`, which the server
    /// checks — and back to the one this server assigned.
    private func ownDomainSection(_ identity: BlueskyIdentity) -> some View {
        Section {
            if identity.customHandle.isEmpty {
                HStack(spacing: AlohaMetrics.space2) {
                    TextField(
                        String(
                            localized: "yourname.example.com",
                            comment: "Bluesky custom handle placeholder"),
                        text: $handleDraft
                    )
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                    .autocorrectionDisabled()
                    Button {
                        Task { await setHandle() }
                    } label: {
                        Text("Use it", comment: "Bluesky custom handle action")
                            .font(.footnote.weight(.semibold))
                    }
                    .disabled(isSaving || !handleDraft.contains("."))
                }
            } else {
                LabeledContent {
                    Text(verbatim: "@\(identity.customHandle)")
                } label: {
                    Text("Your own domain", comment: "Bluesky custom handle row")
                }
                Button(role: .destructive) {
                    Task { await clearHandle() }
                } label: {
                    Text(
                        "Go back to @\(identity.assignedHandle)",
                        comment: "Bluesky custom handle clear action")
                }
                .disabled(isSaving)
            }
        } header: {
            Text("A handle on your own domain", comment: "Bluesky settings section")
        } footer: {
            Text(
                "Your domain must name your Bluesky account first: \(identity.did). Your server may ask for your password before it changes.",
                comment: "Bluesky custom handle explanation")
        }
    }

    /// Follows from here everybody a Bluesky account follows — a move's
    /// first step, or just a way in. Runs in the background; the imports
    /// below say how far it got.
    private var followFromSection: some View {
        Section {
            HStack(spacing: AlohaMetrics.space2) {
                TextField(
                    String(
                        localized: "handle.bsky.social",
                        comment: "Bluesky follow-from placeholder"),
                    text: $followFromDraft
                )
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                Button {
                    Task { await followFrom() }
                } label: {
                    if isQueueingFollows {
                        ProgressView()
                    } else {
                        Text("Follow them", comment: "Bluesky follow-from action")
                            .font(.footnote.weight(.semibold))
                    }
                }
                .disabled(
                    isQueueingFollows
                        || followFromDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Follow who a Bluesky account follows", comment: "Bluesky settings section")
        } footer: {
            Text(
                "Your old Bluesky account, for instance. Everybody it follows is followed from here, a few at a time.",
                comment: "Bluesky follow-from explanation")
        }
    }

    private func setHandle() async {
        let handle = handleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !handle.isEmpty, let current = identity else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            var updated = try await session.client.decode(
                BlueskyIdentity.self, from: .bluesky.setHandle(handle))
            if updated.publishBlocks == nil { updated.publishBlocks = current.publishBlocks }
            identity = updated
            handleDraft = ""
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func clearHandle() async {
        guard let current = identity else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            var updated = try await session.client.decode(
                BlueskyIdentity.self, from: .bluesky.clearHandle)
            if updated.publishBlocks == nil { updated.publishBlocks = current.publishBlocks }
            identity = updated
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func followFrom() async {
        let account = followFromDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !account.isEmpty, !isQueueingFollows else { return }
        isQueueingFollows = true
        defer { isQueueingFollows = false }
        do {
            _ = try await session.client.decode(
                MigrationQueued.self, from: .bluesky.followFrom(account))
            followFromDraft = ""
            errorMessage = nil
            importsReload += 1
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            identity = try await session.client.decode(
                BlueskyIdentity.self, from: .bluesky.identity)
            hasNoIdentity = false
            errorMessage = nil
        } catch APIError.notFound {
            // The server reads Bluesky (this screen is only reachable when it
            // does), so a 404 here is "no identity for this account".
            hasNoIdentity = true
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func setActive(_ active: Bool) async {
        guard let current = identity else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            var updated = try await session.client.decode(
                BlueskyIdentity.self, from: .bluesky.setActive(active))
            if updated.publishBlocks == nil { updated.publishBlocks = current.publishBlocks }
            identity = updated
            errorMessage = nil
        } catch {
            identity = current
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func setPublishBlocks(_ publish: Bool) async {
        guard var current = identity else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let answer = try await session.client.decode(
                BlueskyPublishBlocks.self, from: .bluesky.setPublishBlocks(publish))
            current.publishBlocks = answer.publishBlocks
            identity = current
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
