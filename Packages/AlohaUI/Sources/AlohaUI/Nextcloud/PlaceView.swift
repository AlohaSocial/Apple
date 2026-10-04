// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Public posts from one place: a header with the name and country, then a
/// grid of the pictures, with the text-only posts listed beneath.
public struct PlaceView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.mediaTransition) private var mediaTransition

    private let id: String
    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var place: Status.StatusPlace?
    @State private var statuses: [Status] = []
    @State private var next: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init(
        id: String, session: AccountSession,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.id = id
        self.session = session
        self.onAction = onAction
    }

    private var withMedia: [Status] { statuses.filter { $0.displayed.hasMedia } }
    private var withoutMedia: [Status] { statuses.filter { !$0.displayed.hasMedia } }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1.5), count: 3)

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
                header

                if let errorMessage, !isLoading {
                    VStack(spacing: AlohaMetrics.space2) {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(palette.destructive)
                        Button {
                            Task { await load() }
                        } label: {
                            Text("Retry", comment: "Place retry action")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, AlohaMetrics.space3)
                }

                if !withMedia.isEmpty {
                    LazyVGrid(columns: columns, spacing: 1.5) {
                        ForEach(withMedia) { status in
                            cell(status)
                                .onAppear {
                                    if status.id == statuses.last?.id { Task { await loadMore() } }
                                }
                        }
                    }
                }

                LazyVStack(spacing: 0) {
                    ForEach(withoutMedia) { status in
                        StatusRow(
                            status: status,
                            policy: session.settings.sensitiveMediaPolicy,
                            localHost: session.snapshot.instanceHost,
                            canReact: session.capabilities.emojiReactions,
                            onAction: onAction
                        )
                        .padding(.horizontal, AlohaMetrics.space4)
                        .onAppear {
                            if status.id == statuses.last?.id { Task { await loadMore() } }
                        }
                        Divider().padding(.leading, AlohaMetrics.space4)
                    }
                }

                if statuses.isEmpty && !isLoading && errorMessage == nil {
                    ContentUnavailableView {
                        Text("Nothing from here yet", comment: "Empty place")
                    } description: {
                        Text(
                            "Public posts tagged with this place appear here.",
                            comment: "Place empty detail")
                    }
                    .padding(.top, AlohaMetrics.space6)
                }
            }
        }
        .background(palette.background)
        .overlay {
            if isLoading && statuses.isEmpty { ProgressView() }
        }
        .navigationTitle(title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .refreshable { await load() }
    }

    /// The fetched name, and the screen's own word for a place when the
    /// fetch has not answered — never an empty bar.
    private var title: Text {
        if let name = place?.name, !name.isEmpty { return Text(verbatim: name) }
        return Text("Place", comment: "Place fallback title")
    }

    private var header: some View {
        HStack(spacing: AlohaMetrics.space3) {
            Image(systemName: "mappin.and.ellipse")
                .font(.title)
                .foregroundStyle(palette.accent)
                .frame(width: 44, height: 44)
                .background(palette.surfaceRaised, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(place?.name ?? String(localized: "Place", comment: "Place fallback title"))
                    .font(AlohaType.display)
                if let country = place?.country, !country.isEmpty {
                    Text(country)
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryLabel)
                }
                Text("Public posts made here.", comment: "Place description")
                    .font(AlohaType.meta)
                    .foregroundStyle(palette.tertiaryLabel)
            }
            Spacer()
        }
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.top, AlohaMetrics.space3)
    }

    private func cell(_ status: Status) -> some View {
        let first = status.displayed.mediaAttachments.first
        let isCovered =
            status.displayed.sensitive
            && !session.settings.sensitiveMediaPolicy.allowsAutomaticReveal
        return Button {
            onAction(.openMedia(status: status.displayed, index: 0))
        } label: {
            RemoteImage(
                url: first?.displayImageURL, blurhash: first?.blurhash,
                accessibilityText: isCovered ? nil : first?.description
            )
            .aspectRatio(1, contentMode: .fill)
            .overlay { if isCovered { Rectangle().fill(.ultraThinMaterial) } }
            .clipped()
        }
        .buttonStyle(.plain)
        .mediaTransitionSource(id: first?.id ?? status.id, in: mediaTransition)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let placeTask = session.client.decode(
            Status.StatusPlace.self, from: Endpoint.statusExtras.place(id))
        do {
            let page = try await session.client.page(
                LossyArray<Status>.self, from: Endpoint.statusExtras.placeStatuses(id), limit: 20)
            statuses = page.value.elements
            next = page.mayHaveMore ? page.link.next : nil
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
        // The place itself is worth showing even when its posts failed.
        place = try? await placeTask
    }

    private func loadMore() async {
        guard let next, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await session.client.page(
                LossyArray<Status>.self, following: next, limit: 20)
            let known = Set(statuses.map(\.id))
            statuses += page.value.elements.filter { !known.contains($0.id) }
            self.next = page.mayHaveMore ? page.link.next : nil
            errorMessage = nil
        } catch {
            // The cursor is left where it was, so the next scroll tries again.
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
