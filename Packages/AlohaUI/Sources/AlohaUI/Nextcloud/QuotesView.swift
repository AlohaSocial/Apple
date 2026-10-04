// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The posts quoting a status, newest first (`GET /api/v1/statuses/{id}/quotes`).
public struct QuotesView: View {
    @Environment(\.alohaPalette) private var palette

    private let statusID: String
    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var quotes: [Status] = []
    @State private var next: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init(
        statusID: String, session: AccountSession,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.statusID = statusID
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        List {
            if let errorMessage {
                errorRow(errorMessage)
            }

            ForEach(quotes) { quote in
                StatusRow(
                    status: quote,
                    policy: session.settings.sensitiveMediaPolicy,
                    localHost: session.snapshot.instanceHost,
                    canReact: session.capabilities.emojiReactions,
                    isOwn: quote.displayed.account.id == session.snapshot.serverAccountID,
                    onAction: onAction
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(palette.background)
                .listRowSeparator(.hidden)
                .onAppear {
                    if quote.id == quotes.last?.id { Task { await loadMore() } }
                }
            }

            if quotes.isEmpty && !isLoading && errorMessage == nil {
                ContentUnavailableView {
                    Text("No quotes yet", comment: "Empty quotes")
                } description: {
                    Text("Posts that quote this one appear here.", comment: "Quotes empty detail")
                }
                .listRowSeparator(.hidden)
                .listRowBackground(palette.background)
            }
        }
        .listStyle(.plain)
        .alohaGround(palette)
        .overlay {
            if isLoading && quotes.isEmpty { ProgressView() }
        }
        .navigationTitle(Text("Quotes", comment: "Screen title"))
        .task { await load() }
        .refreshable { await load() }
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.warning)
                .accessibilityHidden(true)
            Text(message).font(.footnote)
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Text("Retry", comment: "Quotes retry action")
            }
            .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(palette.destructive)
        .padding(.vertical, AlohaMetrics.space2)
        .listRowBackground(palette.background)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await session.client.page(
                LossyArray<Status>.self, from: Endpoint.statusExtras.quotes(statusID), limit: 20)
            quotes = page.value.elements
            next = page.mayHaveMore ? page.link.next : nil
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func loadMore() async {
        guard let next, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await session.client.page(
                LossyArray<Status>.self, following: next, limit: 20)
            let known = Set(quotes.map(\.id))
            quotes += page.value.elements.filter { !known.contains($0.id) }
            self.next = page.mayHaveMore ? page.link.next : nil
            errorMessage = nil
        } catch {
            // The cursor is left where it was, so the next scroll tries again.
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
