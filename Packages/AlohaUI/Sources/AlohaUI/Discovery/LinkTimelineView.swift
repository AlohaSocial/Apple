// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The posts sharing one link (`GET /api/v1/timelines/link`): what a trending
/// link opens on Aloha Social, so the conversation about a story is one tap
/// away from the story rather than lost behind it. The link itself is the
/// first row, and opening it is still one tap.
public struct LinkTimelineView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.openURL) private var openURL

    private let url: URL
    private let title: String?
    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var statuses: [Status] = []
    @State private var isLoading = true
    @State private var mayHaveMore = false
    @State private var errorMessage: String?
    @State private var loadID = UUID()

    public init(
        url: URL, title: String?, session: AccountSession,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.url = url
        self.title = title
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        List {
            Section {
                Button {
                    openURL(url)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            if let title, !title.isEmpty {
                                Text(title).font(AlohaType.name).lineLimit(2)
                            }
                            Text(url.host() ?? url.absoluteString)
                                .font(AlohaType.meta)
                                .foregroundStyle(palette.secondaryLabel)
                                .lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: "safari")
                    }
                }
                .accessibilityHint(Text("Opens the link", comment: "Link timeline header hint"))
            }
            .listRowBackground(palette.surfaceRaised)

            if let errorMessage {
                AlohaErrorStrip(message: errorMessage) {
                    Task { await load() }
                }
                .listRowBackground(palette.background)
            }

            ForEach(statuses) { status in
                StatusRow(
                    status: status,
                    policy: session.settings.sensitiveMediaPolicy,
                    localHost: session.snapshot.instanceHost,
                    canReact: session.capabilities.emojiReactions,
                    isOwn: status.displayed.account.id == session.snapshot.serverAccountID,
                    showsCounts: session.settings.showPopularityCounts,
                    onAction: onAction
                )
                .statusRowInteractions(status, session: session, onAction: onAction)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(palette.background)
                .onAppear {
                    if status.id == statuses.last?.id { Task { await loadMore() } }
                }
            }

            if statuses.isEmpty && !isLoading && errorMessage == nil {
                ContentUnavailableView {
                    Text("Nobody here has shared it", comment: "Empty link timeline")
                } description: {
                    Text(
                        "Posts sharing this link will appear here.",
                        comment: "Empty link timeline detail")
                }
                .listRowBackground(palette.background)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .alohaGround(palette)
        .navigationTitle(Text("Shared link", comment: "Screen title"))
        .overlay {
            if isLoading && statuses.isEmpty { SkeletonListRow(person: 4) }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        let request = UUID()
        loadID = request
        isLoading = true
        defer { if loadID == request { isLoading = false } }
        do {
            let page = try await session.client.page(
                LossyArray<Status>.self, from: .socialExtras.linkTimeline(url), limit: 20)
            guard loadID == request else { return }
            statuses = page.value.elements
            mayHaveMore = page.mayHaveMore
            errorMessage = nil
        } catch {
            guard loadID == request else { return }
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Pages by the last row: the route pages by `max_id` like a timeline.
    private func loadMore() async {
        guard mayHaveMore, !isLoading, let last = statuses.last else { return }
        let request = loadID
        isLoading = true
        defer { if loadID == request { isLoading = false } }
        do {
            let page = try await session.client.page(
                LossyArray<Status>.self,
                from: .socialExtras.linkTimeline(url, anchor: .olderThan(last.id)), limit: 20)
            guard loadID == request else { return }
            let known = Set(statuses.map(\.id))
            statuses += page.value.elements.filter { !known.contains($0.id) }
            mayHaveMore = page.mayHaveMore && !page.value.elements.isEmpty
        } catch {
            guard loadID == request else { return }
            mayHaveMore = false
            await session.handle(error)
        }
    }
}
