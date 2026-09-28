// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// People waiting to follow a locked account.
///
/// Part of the navigation because Nextcloud Social carries it in its account
/// menu; a request nobody can see is a request nobody answers.
public struct FollowRequestsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var accounts: [Account] = []
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

            ForEach(accounts) { account in
                HStack(spacing: AlohaMetrics.space3) {
                    Button {
                        onAction(.openProfile(account))
                    } label: {
                        HStack(spacing: AlohaMetrics.space3) {
                            AvatarView(account: account)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.bestDisplayName)
                                    .font(.subheadline.weight(.medium))
                                Text(
                                    account.qualifiedHandle(
                                        localHost: session.snapshot.instanceHost)
                                )
                                .font(.caption)
                                .foregroundStyle(palette.secondaryLabel)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        Text(
                            "Profile of \(account.bestDisplayName)",
                            comment: "Accessibility label for an avatar button"))

                    Spacer(minLength: 0)

                    Button {
                        Task { await decide(account, accept: true) }
                    } label: {
                        Text("Accept", comment: "Follow request action")
                    }
                    .buttonStyle(.alohaProminent)

                    Button(role: .destructive) {
                        Task { await decide(account, accept: false) }
                    } label: {
                        Text("Decline", comment: "Follow request action")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, AlohaMetrics.space1)
            }

            if accounts.isEmpty && !isLoading {
                EmptyStateView(
                    symbol: "person.badge.clock",
                    title: Text("No follow requests", comment: "Empty follow requests"),
                    message: Text(
                        "When your account is locked, people asking to follow you wait here.",
                        comment: "Empty follow requests detail")
                )
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle(Text("Follow requests", comment: "Screen title"))
        .refreshable { await load() }
        .task { await load() }
    }

    /// Answered rows leave at once; the server is told afterwards.
    private func decide(_ account: Account, accept: Bool) async {
        accounts.removeAll { $0.id == account.id }
        let endpoint =
            accept
            ? Endpoint.accounts.authoriseFollowRequest(account.id)
            : Endpoint.accounts.rejectFollowRequest(account.id)
        _ = try? await session.client.send(endpoint)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await session.client.decode(
                LossyArray<Account>.self, from: Endpoint.accounts.followRequests)
            accounts = page.elements
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
