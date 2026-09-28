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

    private static let gutter: Double = 1.5
    private var isOwn: Bool { accountID == session.snapshot.serverAccountID }

    var body: some View {
        LazyVStack(spacing: 0) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(palette.destructive)
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

            if isLoading {
                ProgressView().padding(AlohaMetrics.space4)
            } else if statuses.isEmpty {
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
                    url: first?.previewURL ?? first?.url,
                    blurhash: first?.blurhash,
                    accessibilityText: first?.description ?? target.account.bestDisplayName
                )
                .aspectRatio(1, contentMode: .fill)
                .overlay { if isCovered { Rectangle().fill(.ultraThinMaterial) } }

                if target.mediaAttachments.count > 1 {
                    Image(systemName: "square.on.square.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(6)
                        .shadow(radius: 2)
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
            }
        }
        .mediaTransitionSource(id: first?.id ?? status.id, in: mediaTransition)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await session.client.page(
                LossyArray<Status>.self, from: Endpoint.profile.tagged(accountID, limit: 40),
                limit: 40)
            statuses = page.value.elements
            nextPage = page.mayHaveMore ? page.link.next : nil
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func loadMore() async {
        guard let nextPage, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if let page = try? await session.client.page(
            LossyArray<Status>.self, following: nextPage, limit: 40)
        {
            let known = Set(statuses.map(\.id))
            statuses += page.value.elements.filter { !known.contains($0.id) }
            self.nextPage = page.mayHaveMore ? page.link.next : nil
        } else {
            self.nextPage = nil
        }
    }

    /// The row goes at once; the server is told after. Nothing to undo if
    /// the call fails but a refresh, which puts the photo back.
    private func untag(_ status: Status) async {
        statuses.removeAll { $0.id == status.id }
        do {
            _ = try await session.client.send(
                Endpoint.profile.untagMe(statusID: status.displayed.id))
        } catch {
            await session.handle(error)
            await load()
        }
    }
}
