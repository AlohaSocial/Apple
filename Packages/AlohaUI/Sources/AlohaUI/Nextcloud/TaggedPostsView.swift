// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Photos an account is tagged in: a three-column grid, paged, with "Remove
/// my tag" on the ones you are in yourself. Pixelfed's `tagged` surface, as
/// Nextcloud Social serves it (`GET /api/v1.1/accounts/{id}/tagged`).
public struct TaggedPostsView: View {
    @Environment(\.alohaPalette) private var palette

    private let accountID: String
    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    public init(
        accountID: String, session: AccountSession,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.accountID = accountID
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        ScrollView {
            TaggedGrid(accountID: accountID, session: session, onAction: onAction)
        }
        .background(palette.background)
        .navigationTitle(Text("Tagged", comment: "Screen title"))
    }
}

/// The grid on its own, so the profile can draw it inside its own scroll view.
struct TaggedGrid: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.mediaTransition) private var mediaTransition

    let accountID: String
    let session: AccountSession
    let onAction: (StatusRowAction) -> Void

    @State private var statuses: [Status] = []
    @State private var nextPage: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadID = UUID()
    @State private var removing: Set<String> = []

    private static let gutter: Double = 1.5
    private var isOwn: Bool { accountID == session.snapshot.serverAccountID }

    var body: some View {
        LazyVStack(spacing: 0) {
            if let errorMessage {
                VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                    Label(errorMessage, systemImage: AlohaSymbol.warning)
                        .font(.footnote)
                        .foregroundStyle(palette.destructive)
                    Button {
                        Task { await load() }
                    } label: {
                        Text("Retry", comment: "Tagged photos retry action")
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.glass)
                    .disabled(isLoading || !removing.isEmpty)
                }
                .padding(AlohaMetrics.space3)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Self.gutter), count: 3),
                spacing: Self.gutter
            ) {
                ForEach(statuses) { status in
                    cell(status)
                        .aspectRatio(1, contentMode: .fit)
                        .onAppear {
                            if status.id == statuses.last?.id { Task { await loadMore() } }
                        }
                }
            }

            if isLoading || !removing.isEmpty {
                // A first page, or more arriving, is a list in progress — the
                // shape of three photos — rather than a spinner floating in the
                // middle of nothing.
                SkeletonListRow(person: 3)
                    .padding(AlohaMetrics.space4)
            } else if statuses.isEmpty && errorMessage == nil {
                ContentUnavailableView {
                    Text("Not tagged anywhere", comment: "Empty tagged photos")
                } description: {
                    Text(
                        "Photos this account is tagged in appear here.",
                        comment: "Tagged photos explanation")
                }
                .padding(.top, AlohaMetrics.space6)
            }
        }
        .task { await load() }
    }

    private func cell(_ status: Status) -> some View {
        let target = status.displayed
        let first = target.mediaAttachments.first
        let isCovered =
            target.sensitive
            && !session.settings.sensitiveMediaPolicy.allowsAutomaticReveal

        return Button {
            if first != nil {
                onAction(.openMedia(status: target, index: 0))
            } else {
                onAction(.open(status))
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                RemoteImage(
                    url: first?.displayImageURL,
                    blurhash: first?.blurhash,
                    accessibilityText:
                        isCovered ? nil : (first?.description ?? target.account.bestDisplayName)
                )
                .aspectRatio(1, contentMode: .fill)
                .overlay { if isCovered { Rectangle().fill(.ultraThinMaterial) } }

                if target.mediaAttachments.count > 1 {
                    Image(systemName: "square.on.square.fill")
                        .font(.caption)
                        .foregroundStyle(palette.label)
                        .padding(AlohaMetrics.space2)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .clipped()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onAction(.open(status))
            } label: {
                Label {
                    Text("Open post", comment: "Tagged photo action")
                } icon: {
                    Image(systemName: "arrow.up.right.square")
                }
            }
            Button {
                onAction(.openProfile(target.account))
            } label: {
                Label {
                    Text("By \(target.account.bestDisplayName)", comment: "Tagged photo action")
                } icon: {
                    Image(systemName: AlohaSymbol.profile)
                }
            }
            if isOwn {
                Divider()
                Button(role: .destructive) {
                    Task { await untag(status) }
                } label: {
                    Label {
                        Text("Remove my tag", comment: "Tagged photo action")
                    } icon: {
                        Image(systemName: "tag.slash")
                    }
                }
                .disabled(isLoading || removing.contains(status.id))
            }
        }
        .mediaTransitionSource(id: first?.id ?? status.id, in: mediaTransition)
    }

    private func load() async {
        guard removing.isEmpty else { return }
        let request = UUID()
        loadID = request
        isLoading = true
        errorMessage = nil
        defer { if loadID == request { isLoading = false } }
        do {
            let page = try await session.client.page(
                LossyArray<Status>.self, from: Endpoint.profile.tagged(accountID, limit: 40),
                limit: 40)
            guard !Task.isCancelled, loadID == request else { return }
            statuses = page.value.elements
            nextPage = page.mayHaveMore ? page.link.next : nil
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, loadID == request else { return }
            await session.handle(error)
            guard !Task.isCancelled, loadID == request else { return }
            errorMessage = (error as? APIError)?.errorDescription
                ?? String(localized: "Tagged posts could not be loaded. Please try again.")
        }
    }

    private func loadMore() async {
        guard let nextPage, !isLoading, removing.isEmpty else { return }
        let request = loadID
        isLoading = true
        defer { if loadID == request { isLoading = false } }
        do {
            let page = try await session.client.page(
                LossyArray<Status>.self, following: nextPage, limit: 40)
            guard !Task.isCancelled, loadID == request else { return }
            let known = Set(statuses.map(\.id))
            statuses += page.value.elements.filter { !known.contains($0.id) }
            self.nextPage = page.mayHaveMore ? page.link.next : nil
            errorMessage = nil
        } catch {
            // The cursor is left where it was, so the next scroll tries again.
            guard !Task.isCancelled, loadID == request else { return }
            await session.handle(error)
            guard !Task.isCancelled, loadID == request else { return }
            errorMessage = (error as? APIError)?.errorDescription
                ?? String(localized: "More tagged posts could not be loaded. Please try again.")
        }
    }

    /// Optimistic removal rolls back only this row, preserving other results.
    private func untag(_ status: Status) async {
        guard !isLoading, let index = statuses.firstIndex(where: { $0.id == status.id }),
            removing.insert(status.id).inserted else { return }
        defer { removing.remove(status.id) }
        errorMessage = nil
        statuses.removeAll { $0.id == status.id }
        do {
            _ = try await session.client.send(
                Endpoint.profile.untagMe(statusID: status.displayed.id))
        } catch {
            if !statuses.contains(where: { $0.id == status.id }) {
                statuses.insert(status, at: min(index, statuses.count))
            }
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
                ?? String(localized: "Your tag could not be removed. Please try again.")
        }
    }
}
