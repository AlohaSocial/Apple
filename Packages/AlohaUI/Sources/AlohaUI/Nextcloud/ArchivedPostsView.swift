// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Your archived posts: off the profile and out of every timeline, but not
/// deleted and never federated as gone (Pixelfed's notion). Unarchive puts
/// one back.
public struct ArchivedPostsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var statuses: [Status] = []
    @State private var next: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init(session: AccountSession, onAction: @escaping (StatusRowAction) -> Void) {
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        List {
            if let errorMessage {
                errorRow(errorMessage)
            }

            ForEach(statuses) { status in
                StatusRow(
                    status: status,
                    policy: session.settings.sensitiveMediaPolicy,
                    localHost: session.snapshot.instanceHost,
                    isOwn: true,
                    onAction: onAction
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(palette.background)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing) {
                    Button {
                        Task { await unarchive(status) }
                    } label: {
                        Label {
                            Text("Unarchive", comment: "Archived posts action")
                        } icon: {
                            Image(systemName: "tray.and.arrow.up")
                        }
                    }
                    .tint(palette.accent)
                }
                .onAppear {
                    if status.id == statuses.last?.id { Task { await loadMore() } }
                }
            }

            if statuses.isEmpty && !isLoading && errorMessage == nil {
                ContentUnavailableView {
                    Text("Nothing archived", comment: "Empty archived posts")
                } description: {
                    Text(
                        "Archiving takes a post off your profile without deleting it. Find it here to bring it back.",
                        comment: "Archived posts explanation")
                }
                .listRowSeparator(.hidden)
                .listRowBackground(palette.background)
            }
        }
        .listStyle(.plain)
        .alohaGround(palette)
        .overlay {
            if isLoading && statuses.isEmpty { ProgressView() }
        }
        .navigationTitle(Text("Archived posts", comment: "Screen title"))
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
                Text("Retry", comment: "Archived posts retry action")
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
                LossyArray<Status>.self, from: Endpoint.statusExtras.archived(), limit: 20)
            statuses = page.value.elements.map(marked)
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
            let known = Set(statuses.map(\.id))
            statuses += page.value.elements.filter { !known.contains($0.id) }.map(marked)
            self.next = page.mayHaveMore ? page.link.next : nil
            errorMessage = nil
        } catch {
            // The cursor is left where it was, so the next scroll tries again.
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    /// The list route does not say so on each row; this screen knows.
    private func marked(_ status: Status) -> Status {
        var copy = status
        copy.archived = true
        return copy
    }

    private func unarchive(_ status: Status) async {
        let previous = statuses
        statuses.removeAll { $0.id == status.id }
        do {
            _ = try await session.client.send(Endpoint.statusExtras.unarchive(status.displayed.id))
            var updated = status.displayed
            updated.archived = false
            try? await session.timelineStore.updateStatus(accountID: session.id, status: updated)
            errorMessage = nil
        } catch {
            statuses = previous
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
