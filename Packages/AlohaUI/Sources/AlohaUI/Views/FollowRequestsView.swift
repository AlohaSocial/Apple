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
                errorStrip(errorMessage)
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

                    // One family and one size for the pair: Accept was 44pt
                    // against a 32pt Decline, which read as one answer being
                    // the important one.
                    Button {
                        Task { await decide(account, accept: true) }
                    } label: {
                        Text("Accept", comment: "Follow request action")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.regular)

                    Button(role: .destructive) {
                        Task { await decide(account, accept: false) }
                    } label: {
                        Text("Decline", comment: "Follow request action")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.regular)
                }
                .padding(.vertical, AlohaMetrics.space1)
                .listRowBackground(palette.background)
            }

            if accounts.isEmpty && !isLoading && errorMessage == nil {
                EmptyStateView(
                    symbol: "person.badge.clock",
                    title: Text("No follow requests", comment: "Empty follow requests"),
                    message: Text(
                        "When your account is locked, people asking to follow you wait here.",
                        comment: "Empty follow requests detail")
                )
                .listRowBackground(palette.background)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .alohaGround(palette)
        .overlay {
            if isLoading && accounts.isEmpty { ProgressView() }
        }
        .navigationTitle(Text("Follow requests", comment: "Screen title"))
        .refreshable { await load() }
        .task { await load() }
    }

    private func errorStrip(_ message: String) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.warning)
            Text(message).font(.caption)
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Text("Retry", comment: "Error strip action")
            }
            .font(.caption.weight(.semibold))
        }
        .foregroundStyle(palette.destructive)
        .padding(.vertical, AlohaMetrics.space2)
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
    }

    /// Answered rows leave at once; a refusal puts the row back where it was
    /// and says why, rather than losing the request silently.
    private func decide(_ account: Account, accept: Bool) async {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts.remove(at: index)
        let endpoint =
            accept
            ? Endpoint.accounts.authoriseFollowRequest(account.id)
            : Endpoint.accounts.rejectFollowRequest(account.id)
        do {
            _ = try await session.client.send(endpoint)
            errorMessage = nil
        } catch {
            if !accounts.contains(where: { $0.id == account.id }) {
                accounts.insert(account, at: min(index, accounts.count))
            }
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
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
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
