// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// One starter pack: its accounts, resolved, and a button that follows every
/// one of them. Handles the server could not resolve are listed as such rather
/// than silently dropped, with a retry.
public struct StarterPackView: View {
    @Environment(\.alohaPalette) private var palette

    private let slug: String
    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var pack: StarterPack?
    @State private var isLoading = true
    @State private var isFollowing = false
    @State private var followedCount: Int?
    @State private var errorMessage: String?

    public init(
        slug: String, session: AccountSession,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.slug = slug
        self.session = session
        self.onAction = onAction
    }

    /// Handles the pack names that came back without an account.
    private var unresolved: [String] {
        guard let pack else { return [] }
        let resolved = Set(pack.accounts.map { $0.acct.lowercased() })
        return pack.handles.filter { handle in
            let bare = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
            return !resolved.contains(bare.lowercased())
        }
    }

    public var body: some View {
        List {
            if let pack {
                Section {
                    VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
                        if !pack.description.isEmpty {
                            Text(pack.description)
                                .font(.body)
                                .foregroundStyle(palette.secondaryLabel)
                        }
                        followAllButton(pack)
                    }
                    .listRowBackground(palette.background)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, AlohaMetrics.space1)
                }

                Section {
                    ForEach(pack.accounts) { account in
                        Button {
                            onAction(.openProfile(account))
                        } label: {
                            AccountRow(account: account, localHost: session.snapshot.instanceHost)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(palette.background)
                        .accessibilityLabel(Text(account.bestDisplayName))
                    }
                } header: {
                    Text(
                        "^[\(pack.accounts.count) account](inflect: true)",
                        comment: "Starter pack section")
                }

                if !unresolved.isEmpty {
                    Section {
                        ForEach(unresolved, id: \.self) { handle in
                            Text(handle)
                                .font(.subheadline)
                                .foregroundStyle(palette.tertiaryLabel)
                                .listRowBackground(palette.background)
                        }
                        Button {
                            Task { await load() }
                        } label: {
                            Text("Try again", comment: "Starter pack retry action")
                        }
                        .listRowBackground(palette.background)
                    } header: {
                        Text("Couldn't be reached", comment: "Starter pack section")
                    } footer: {
                        Text(
                            "Their servers didn't answer this time.",
                            comment: "Starter pack unresolved footer")
                    }
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(palette.background)
                    .listRowSeparator(.hidden)
            }

            if let errorMessage {
                errorStrip(errorMessage)
            }
        }
        .listStyle(.plain)
        .alohaGround(palette)
        .navigationTitle(
            pack.map { Text($0.name) } ?? Text("Starter pack", comment: "Screen title")
        )
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .refreshable { await load() }
    }

    private func errorStrip(_ message: String) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.warning)
            Text(message).font(.footnote)
            Spacer()
            Button {
                // A follow that failed is retried as a follow; anything else
                // is a pack that did not come in, so it is loaded again.
                Task {
                    if pack != nil && followedCount == nil {
                        await followAll()
                    } else {
                        await load()
                    }
                }
            } label: {
                Text("Retry", comment: "Starter pack retry action")
            }
            .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(palette.destructive)
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
    }

    private func followAllButton(_ pack: StarterPack) -> some View {
        Button {
            Task { await followAll() }
        } label: {
            HStack(spacing: AlohaMetrics.space2) {
                if isFollowing {
                    ProgressView().controlSize(.small)
                    Text("Following everyone…", comment: "Starter pack action in progress")
                } else if let followedCount {
                    Image(systemName: "checkmark")
                    Text(
                        "Now following ^[\(followedCount) account](inflect: true)",
                        comment: "Starter pack action done")
                } else {
                    Image(systemName: "person.badge.plus")
                    Text("Follow everyone", comment: "Starter pack action")
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isFollowing || followedCount != nil || pack.accounts.isEmpty)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            pack = try await session.client.decode(
                StarterPack.self, from: Endpoint.discovery.starterPack(slug))
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func followAll() async {
        guard let pack else { return }
        isFollowing = true
        defer { isFollowing = false }
        do {
            let response = try await session.client.send(
                Endpoint.discovery.followStarterPack(pack.slug))
            // The server answers with whom it followed; the count is the
            // whole of the reply this screen needs.
            let followed =
                (try? JSONDecoder().decode(LossyArray<Account>.self, from: response.data))?
                .elements.count
            followedCount = followed ?? pack.accounts.count
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
