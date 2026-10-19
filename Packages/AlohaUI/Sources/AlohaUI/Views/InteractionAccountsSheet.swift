// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Who favourited a post, and who boosted it.
///
/// Aloha Social answers with the accounts it holds and reads the rest from
/// where the post lives in the background, saying so with
/// `X-Social-Filling: 1`; the sheet asks again while that is true, the way
/// the server's own web app does.
struct InteractionAccountsSheet: View {
    enum Kind: String, CaseIterable, Identifiable {
        case favourites
        case boosts
        var id: String { rawValue }
    }

    @Environment(\.alohaPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    let statusID: String
    let session: AccountSession
    let onOpenProfile: (Account) -> Void

    @State var kind: Kind
    @State private var accounts: [Kind: [Account]] = [:]
    @State private var next: [Kind: URL] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    AlohaErrorStrip(message: errorMessage) {
                        Task { await load(kind) }
                    }
                    .listRowBackground(palette.background)
                }

                ForEach(accounts[kind] ?? []) { account in
                    Button {
                        dismiss()
                        onOpenProfile(account)
                    } label: {
                        AccountRow(account: account, localHost: session.snapshot.instanceHost)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(palette.background)
                    .onAppear {
                        if account.id == accounts[kind]?.last?.id { Task { await loadMore(kind) } }
                    }
                }

                if isLoading {
                    SkeletonListRow(person: 3)
                        .listRowBackground(palette.background)
                        .listRowSeparator(.hidden)
                } else if accounts[kind]?.isEmpty == true, errorMessage == nil {
                    ContentUnavailableView {
                        emptyTitle
                    }
                    .listRowBackground(palette.background)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .alohaGround(palette)
            .navigationTitle(title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker(selection: $kind) {
                        Text("Favourites", comment: "Who favourited a post").tag(Kind.favourites)
                        Text("Boosts", comment: "Who boosted a post").tag(Kind.boosts)
                    } label: {
                        title
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", comment: "Close the list of who favourited or boosted")
                    }
                }
            }
            .task(id: kind) {
                if accounts[kind] == nil { await load(kind) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var title: Text {
        switch kind {
        case .favourites: Text("Favourited by", comment: "Title of the list of who favourited")
        case .boosts: Text("Boosted by", comment: "Title of the list of who boosted")
        }
    }

    private var emptyTitle: Text {
        switch kind {
        case .favourites: Text("No favourites yet", comment: "Empty list of who favourited")
        case .boosts: Text("No boosts yet", comment: "Empty list of who boosted")
        }
    }

    private func endpoint(_ kind: Kind) -> Endpoint {
        switch kind {
        case .favourites: Endpoint.statuses.favouritedBy(statusID, limit: 80)
        case .boosts: Endpoint.statuses.rebloggedBy(statusID, limit: 80)
        }
    }

    private func load(_ kind: Kind) async {
        isLoading = true
        defer { isLoading = false }
        let policy = FillingRetryPolicy()
        var attempt = 0
        do {
            while true {
                attempt += 1
                let (page, response) = try await session.client.decodeWithResponse(
                    [Account].self, from: endpoint(kind))
                accounts[kind] = page
                next[kind] = response.link.next
                errorMessage = nil
                guard let delay = policy.delay(after: attempt, filling: SocialFilling(response))
                else { return }
                try await Task.sleep(for: delay)
            }
        } catch is CancellationError {
            return
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Mastodon pages these by `Link`; Aloha Social sends none and answers
    /// the whole list at once.
    private func loadMore(_ kind: Kind) async {
        guard let url = next[kind] else { return }
        next[kind] = nil
        do {
            let page = try await session.client.page([Account].self, following: url, limit: 80)
            let known = Set((accounts[kind] ?? []).map(\.id))
            accounts[kind, default: []] += page.value.filter { !known.contains($0.id) }
            next[kind] = page.link.next
        } catch {
            await session.handle(error)
        }
    }
}
