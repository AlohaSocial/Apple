// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import AlohaStore
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
    @State private var loadID = UUID()
    @State private var retryOlder = false
    /// The reader's filters. Who quotes a post is anyone at all, most of
    /// them people the reader does not follow: the public context.
    @State private var verdicts = FilterVerdicts(context: .public)

    /// Left out at drawing rather than at loading, so the page cursor still
    /// counts what the server sent.
    private var shownQuotes: [Status] { verdicts.kept(quotes) }

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

            ForEach(shownQuotes) { quote in
                StatusRow(
                    status: quote,
                    policy: session.settings.sensitiveMediaPolicy,
                    localHost: session.snapshot.instanceHost,
                    filterWarning: verdicts.warning(for: quote),
                    canReact: session.capabilities.emojiReactions,
                    isOwn: quote.displayed.account.id == session.snapshot.serverAccountID,
                    showsCounts: session.settings.showPopularityCounts,
                    onAction: onAction
                )
                .statusRowInteractions(quote, session: session, onAction: onAction)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(palette.background)
                .listRowSeparator(.hidden)
                .onAppear {
                    if quote.id == shownQuotes.last?.id { Task { await loadMore() } }
                }
            }

            if isLoading && !quotes.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(palette.background)
                    .listRowSeparator(.hidden)
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
        .environment(\.filterVerdicts, verdicts)
        .onStatusesRemoved(for: session) { removal in
            quotes.removeAll { removal.removes($0) }
        }
        .overlay {
            if isLoading && quotes.isEmpty {
                // A first page arriving is a list in progress, not a blank
                // screen with a spinner floating over it.
                SkeletonListRow(person: 4)
                    .listRowBackground(palette.background)
                    .listRowSeparator(.hidden)
            }
        }
        .navigationTitle(Text("Quotes", comment: "Screen title"))
        .task { await load() }
        .refreshable { await load() }
    }

    private func errorRow(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            Label(message, systemImage: AlohaSymbol.warning)
                .font(.footnote)
                .foregroundStyle(palette.destructive)
            Button {
                Task {
                    if retryOlder { await loadMore() } else { await load() }
                }
            } label: {
                Text("Retry", comment: "Quotes retry action")
            }
            .font(.footnote.weight(.semibold))
            .alohaGlassButtonStyle()
            .disabled(isLoading)
        }
        .padding(.vertical, AlohaMetrics.space2)
        .listRowBackground(palette.background)
    }

    private func load() async {
        let request = UUID()
        loadID = request
        isLoading = true
        errorMessage = nil
        retryOlder = false
        defer { if loadID == request { isLoading = false } }
        do {
            let page = try await session.client.page(
                LossyArray<Status>.self, from: Endpoint.statusExtras.quotes(statusID), limit: 20)
            await verdicts.prepare(page.value.elements, session: session)
            guard !Task.isCancelled, loadID == request else { return }
            quotes = page.value.elements
            next = page.mayHaveMore ? page.link.next : nil
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, loadID == request else { return }
            await session.handle(error)
            guard !Task.isCancelled, loadID == request else { return }
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "Quotes could not be loaded. Please try again.")
        }
    }

    private func loadMore() async {
        guard let next, !isLoading else { return }
        let request = loadID
        isLoading = true
        errorMessage = nil
        defer { if loadID == request { isLoading = false } }
        do {
            let page = try await session.client.page(
                LossyArray<Status>.self, following: next, limit: 20)
            await verdicts.warm(page.value.elements)
            guard !Task.isCancelled, loadID == request else { return }
            let known = Set(quotes.map(\.id))
            quotes += page.value.elements.filter { !known.contains($0.id) }
            self.next = page.mayHaveMore ? page.link.next : nil
            errorMessage = nil
        } catch {
            // The cursor is left where it was, so the next scroll tries again.
            guard !Task.isCancelled, loadID == request else { return }
            await session.handle(error)
            guard !Task.isCancelled, loadID == request else { return }
            retryOlder = true
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "More quotes could not be loaded. Please try again.")
        }
    }
}
