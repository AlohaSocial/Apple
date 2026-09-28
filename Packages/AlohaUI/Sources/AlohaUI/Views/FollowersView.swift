// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Which of the two lists a profile stat opens.
public enum FollowListKind: Sendable, Hashable {
    case followers, following
}

/// The people who follow an account, or whom it follows: one row each with a
/// follow button that reflects your own relationship, paged by the `Link`
/// header the server sends.
public struct FollowersView: View {
    @Environment(\.alohaPalette) private var palette

    private let accountID: String
    private let kind: FollowListKind
    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var accounts: [Account] = []
    @State private var relationships: [String: Relationship] = [:]
    @State private var nextPage: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private static let pageSize = 40

    public init(
        accountID: String, kind: FollowListKind, session: AccountSession,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.accountID = accountID
        self.kind = kind
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(palette.destructive)
            }

            ForEach(accounts) { account in
                FollowableAccountRow(
                    account: account, relationship: relationships[account.id],
                    session: session, onAction: onAction
                ) { updated in
                    relationships[account.id] = updated
                }
                .onAppear {
                    if account.id == accounts.last?.id { Task { await loadMore() } }
                }
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else if accounts.isEmpty {
                ContentUnavailableView {
                    switch kind {
                    case .followers: Text("No followers yet", comment: "Empty followers")
                    case .following: Text("Not following anyone", comment: "Empty following")
                    }
                } description: {
                    if kind == .followers {
                        Text(
                            "A remote server may keep its list to itself; the count above is what it says.",
                            comment: "Empty followers explanation")
                    }
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .task { await load() }
        .refreshable { await load() }
    }

    private var title: Text {
        switch kind {
        case .followers: Text("Followers", comment: "Screen title")
        case .following: Text("Following", comment: "Screen title")
        }
    }

    private var endpoint: Endpoint {
        switch kind {
        case .followers: Endpoint.accounts.followers(accountID, limit: Self.pageSize)
        case .following: Endpoint.accounts.following(accountID, limit: Self.pageSize)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await session.client.page(
                LossyArray<Account>.self, from: endpoint, limit: Self.pageSize)
            accounts = page.value.elements
            nextPage = page.mayHaveMore ? page.link.next : nil
            errorMessage = nil
            await loadRelationships(for: accounts)
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func loadMore() async {
        guard let nextPage, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard
            let page = try? await session.client.page(
                LossyArray<Account>.self, following: nextPage, limit: Self.pageSize)
        else {
            self.nextPage = nil
            return
        }
        let known = Set(accounts.map(\.id))
        let fresh = page.value.elements.filter { !known.contains($0.id) }
        accounts += fresh
        self.nextPage = page.mayHaveMore ? page.link.next : nil
        await loadRelationships(for: fresh)
    }

    /// One request per page rather than one per row.
    private func loadRelationships(for batch: [Account]) async {
        let ids = batch.map(\.id).filter { $0 != session.snapshot.serverAccountID }
        guard !ids.isEmpty else { return }
        let found =
            (try? await session.client.decode(
                LossyArray<Relationship>.self, from: Endpoint.accounts.relationships(ids)))?
            .elements ?? []
        for relationship in found { relationships[relationship.id] = relationship }
    }
}

/// One person in a list of people: avatar, name, handle, and a follow button
/// whose state is the real relationship.
///
/// `AccountRow` in `SearchView` is the plain, non-interactive version of the
/// same row; this one is the version that can act, and the two are deliberately
/// separate rather than one row with half its arguments unused.
struct FollowableAccountRow: View {
    @Environment(\.alohaPalette) private var palette

    let account: Account
    let relationship: Relationship?
    let session: AccountSession
    let onAction: (StatusRowAction) -> Void
    let onRelationshipChange: (Relationship) -> Void

    @State private var isBusy = false

    private var isSelf: Bool { account.id == session.snapshot.serverAccountID }

    var body: some View {
        HStack(spacing: AlohaMetrics.space3) {
            Button {
                onAction(.openProfile(account))
            } label: {
                HStack(spacing: AlohaMetrics.space3) {
                    AvatarView(account: account)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.bestDisplayName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(account.qualifiedHandle(localHost: session.snapshot.instanceHost))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if relationship?.followedBy == true {
                            Text("Follows you", comment: "Relationship badge")
                                .font(AlohaType.micro)
                                .foregroundStyle(palette.tertiaryLabel)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                Text(
                    "Profile of \(account.bestDisplayName)",
                    comment: "Accessibility label for an avatar button"))

            Spacer(minLength: 0)

            if !isSelf {
                // Two concrete styles rather than a ternary between them: the
                // two are different types, so only a branch can choose.
                if relationship?.following == true {
                    followButton.buttonStyle(.bordered)
                } else {
                    followButton.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.vertical, AlohaMetrics.space1)
    }

    private var followButton: some View {
        Button {
            Task { await toggleFollow() }
        } label: {
            if relationship?.following == true {
                Text("Following", comment: "Follow button state")
            } else if relationship?.requested == true {
                Text("Requested", comment: "Follow button state")
            } else {
                Text("Follow", comment: "Follow button action")
            }
        }
        .controlSize(.small)
        .disabled(isBusy || relationship == nil)
    }

    private func toggleFollow() async {
        guard let relationship else { return }
        isBusy = true
        defer { isBusy = false }
        let isFollowing = relationship.following || relationship.requested
        let endpoint =
            isFollowing
            ? Endpoint.accounts.simpleAction(account.id, "unfollow")
            : Endpoint.accounts.follow(account.id)
        do {
            onRelationshipChange(try await session.client.decode(Relationship.self, from: endpoint))
        } catch {
            await session.handle(error)
        }
    }
}
