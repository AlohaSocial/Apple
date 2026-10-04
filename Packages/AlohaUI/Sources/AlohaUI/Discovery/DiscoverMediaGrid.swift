// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// "Pictures people are looking at" and "Videos people are watching": a
/// square grid of trending posts, from Pixelfed's discover route where the
/// server has it and from Mastodon's trending statuses everywhere else.
struct DiscoverMediaGrid: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.mediaTransition) private var mediaTransition

    enum Media: String {
        case image, video

        nonisolated func index(in attachments: [MediaAttachment]) -> Int? {
            attachments.firstIndex { self == .video ? $0.isVideo : $0.type == .image }
        }
    }

    let session: AccountSession
    let media: Media
    let onAction: (StatusRowAction) -> Void

    @State private var statuses: [Status] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private static let gutter: Double = 1.5

    var body: some View {
        ScrollView {
            if let errorMessage {
                errorStrip(errorMessage)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Self.gutter), count: 3),
                spacing: Self.gutter
            ) {
                ForEach(statuses) { status in
                    cell(status)
                        .aspectRatio(1, contentMode: .fit)
                }
            }

            if isLoading && statuses.isEmpty {
                ProgressView().padding(.top, AlohaMetrics.space6)
            } else if statuses.isEmpty && errorMessage == nil {
                ContentUnavailableView {
                    switch media {
                    case .image: Text("No pictures trending", comment: "Empty Discover pictures")
                    case .video: Text("No videos trending", comment: "Empty Discover videos")
                    }
                } description: {
                    Text(
                        "What people here are looking at appears once there is enough of it.",
                        comment: "Empty Discover media detail")
                }
                .padding(.top, AlohaMetrics.space6)
            }
        }
        .background(palette.background)
        .task(id: media) { await load() }
        .refreshable { await load() }
    }

    private func errorStrip(_ message: String) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.warning)
            Text(message).font(.footnote)
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Text("Retry", comment: "Discover media reload action")
            }
            .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(palette.destructive)
        .padding(AlohaMetrics.space3)
    }

    private func cell(_ status: Status) -> some View {
        let target = status.displayed
        let mediaIndex = media.index(in: target.mediaAttachments)
        let first = mediaIndex.map { target.mediaAttachments[$0] }
        let isCovered =
            target.sensitive
            && !session.settings.sensitiveMediaPolicy.allowsAutomaticReveal

        return Button {
            if media == .video || first?.type.isPlayable == true {
                onAction(.watch(status))
            } else {
                onAction(.openMedia(status: target, index: mediaIndex ?? 0))
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                RemoteImage(
                    url: first?.displayImageURL,
                    blurhash: first?.blurhash,
                    accessibilityText: first?.description
                )
                .aspectRatio(1, contentMode: .fill)
                .overlay { if isCovered { Rectangle().fill(.ultraThinMaterial) } }

                if target.mediaAttachments.count > 1 {
                    Image(systemName: "square.on.square.fill")
                        .font(.caption)
                        .foregroundStyle(palette.label)
                        .padding(AlohaMetrics.space2)
                        .glassEffect(.regular, in: Capsule())
                        .padding(AlohaMetrics.space1)
                        .accessibilityHidden(true)
                } else if first?.type.isPlayable == true {
                    Image(systemName: AlohaSymbol.play)
                        .font(.caption)
                        .foregroundStyle(palette.label)
                        .padding(AlohaMetrics.space2)
                        .glassEffect(.regular, in: Capsule())
                        .padding(AlohaMetrics.space1)
                        .accessibilityHidden(true)
                }
            }
            .clipped()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label(for: target, alt: first?.description))
        .mediaTransitionSource(id: first?.id ?? target.id, in: mediaTransition)
    }

    /// What the cell says out loud: whose post it is, and the alt text the
    /// picture arrived with when there is one.
    private func label(for status: Status, alt: String?) -> Text {
        var spoken = String(
            localized: "Post by \(status.account.bestDisplayName)",
            comment: "Discover grid cell label")
        if let alt, !alt.isEmpty {
            spoken += ", " + alt
        }
        return Text(verbatim: spoken)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page: [Status]
            if session.capabilities.isNextcloudSocial {
                page = try await session.client.decode(
                    LossyArray<Status>.self,
                    from: Endpoint.discovery.discoverPosts(media: media.rawValue)
                ).elements
            } else {
                // Mastodon ranks posts, not pictures; keep the ones carrying
                // what this grid is for.
                page = try await session.client.decode(
                    LossyArray<Status>.self,
                    from: Endpoint.discovery.trendingStatuses(limit: 40)
                ).elements
            }
            statuses = page.filter { status in
                let attachments = status.displayed.mediaAttachments
                return media.index(in: attachments) != nil
            }
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? String(localized: "Media could not be loaded. Please try again.")
        }
    }
}
