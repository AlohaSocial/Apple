// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaMedia
import AlohaModels
import AlohaNetwork
import AlohaStore
import SwiftUI

/// Long-form video the way a video app lays it out: a Continue Watching shelf,
/// then one edge-to-edge 16:9 thumbnail after another, each with the channel
/// avatar, a two-line title and a byline. Tapping opens the watch page.
public struct VideoModeView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let session: AccountSession
    private let source: TimelineSource
    private let onAction: (StatusRowAction) -> Void

    @State private var model: TimelineModel
    @State private var continueWatching: [ContinueWatchingItem] = []
    @State private var watched: [String: Double] = [:]

    public init(
        session: AccountSession, source: TimelineSource,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.session = session
        self.source = source
        self.onAction = onAction
        _model = State(
            initialValue: TimelineModel(
                key: TimelineKey(mode: .video, source: source), session: session))
    }

    private var statuses: [Status] {
        model.rows.compactMap(\.status).filter { status in
            status.displayed.mediaAttachments.contains(where: { $0.isVideo })
        }
    }

    /// Cards run edge to edge on a phone, and sit in a padded grid elsewhere.
    private var isCompact: Bool {
        #if os(iOS)
            sizeClass == .compact
        #else
            false
        #endif
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: isCompact ? AlohaMetrics.space5 : AlohaMetrics.space4) {
                if !continueWatching.isEmpty { continueShelf }

                ForEach(statuses) { status in
                    VideoCard(
                        status: status,
                        policy: session.settings.sensitiveMediaPolicy,
                        localHost: session.snapshot.instanceHost,
                        progress: watched[status.displayed.id],
                        isEdgeToEdge: isCompact,
                        showsCounts: session.settings.showPopularityCounts,
                        onAction: onAction
                    )
                    .onAppear {
                        if status.id == statuses.last?.id {
                            Task { await model.loadOlder() }
                        }
                    }
                }

                if statuses.isEmpty && !model.isRefreshing { emptyState }
            }
            .padding(.horizontal, isCompact ? 0 : AlohaMetrics.space4)
            .padding(.vertical, AlohaMetrics.space3)
        }
        .background(palette.background)
        .toolbar {
            // Your channels: the PeerTube notion of what a video belongs to.
            if session.capabilities.isNextcloudSocial {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: Route.channels) {
                        Label {
                            Text("Your channels", comment: "Video mode toolbar action")
                        } icon: {
                            Image(systemName: "tv")
                        }
                    }
                    .accessibilityLabel(Text("Your channels", comment: "Video mode toolbar action"))
                }
            }
        }
        .refreshable {
            await model.refresh()
            await loadContinueWatching()
        }
        .task {
            await model.appear()
            await loadContinueWatching()
        }
    }

    private var continueShelf: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            Text("Continue watching", comment: "Video mode shelf")
                .font(AlohaType.section)
                .padding(.horizontal, isCompact ? AlohaMetrics.space3 : 0)

            ScrollView(.horizontal) {
                HStack(spacing: AlohaMetrics.space3) {
                    ForEach(continueWatching) { item in
                        if let status = item.status {
                            Button {
                                onAction(.watch(status))
                            } label: {
                                continueCard(status, fraction: item.fraction)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await forget(item) }
                                } label: {
                                    Text("Remove from Continue Watching", comment: "Video action")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, isCompact ? AlohaMetrics.space3 : 0)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func continueCard(_ status: Status, fraction: Double) -> some View {
        let attachment = status.displayed.mediaAttachments.first(where: { $0.isVideo })

        return VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
            ZStack(alignment: .bottom) {
                RemoteImage(url: attachment?.previewURL, blurhash: attachment?.blurhash)
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(width: 220, height: 124)
                    .clipShape(
                        RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
                    )

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.black.opacity(0.4))
                        Rectangle()
                            .fill(palette.accent)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: 3)
            }
            .frame(width: 220)

            Text(VideoTitle.of(status))
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .frame(width: 220, alignment: .leading)
            Text(status.displayed.account.bestDisplayName)
                .font(.caption2)
                .foregroundStyle(palette.secondaryLabel)
                .lineLimit(1)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Text("No videos yet", comment: "Empty Video mode")
        } description: {
            if !session.capabilities.onlyVideoFilter {
                Text(
                    "This server can't filter by media type, so results may be sparse.",
                    comment: "Empty mode explanation")
            } else {
                Text("Follow someone who posts video.", comment: "Empty Video detail")
            }
        }
        .padding(.top, AlohaMetrics.space6)
    }

    /// Excludes anything barely started and anything finished — the server
    /// drops those itself, and the client mirrors it.
    private func loadContinueWatching() async {
        if session.capabilities.watchPositions {
            continueWatching =
                (try? await session.client.decode(
                    LossyArray<ContinueWatchingItem>.self,
                    from: Endpoint.video.continueWatching()))?.elements ?? []
        }
        // Locally remembered, so a card still shows the bar it had before the
        // shelf got a chance to load — or while the server refuses to.
        watched =
            ((try? await session.supportStore.watchFractions(accountID: session.id)) ?? [:])
    }

    private func forget(_ item: ContinueWatchingItem) async {
        continueWatching.removeAll { $0.id == item.id }
        _ = try? await session.client.send(Endpoint.video.forgetWatched(item.statusID))
    }
}

/// The one rule for what a video is called: its content warning if it has
/// one, else the first line of the body, else a placeholder.
enum VideoTitle {
    static func of(_ status: Status) -> String {
        let target = status.displayed
        if !target.spoilerText.isEmpty { return target.spoilerText }
        let plain = StatusHTMLParser().plainText(target.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let first = plain.split(separator: "\n").first.map(String.init) ?? plain
        return first.isEmpty
            ? String(localized: "Untitled video", comment: "Video with no text") : first
    }
}

/// A 16:9 thumbnail with a duration badge and a watched-progress bar, then
/// the channel avatar, the title and a byline.
public struct VideoCard: View {
    @Environment(\.alohaPalette) private var palette

    private let status: Status
    private let policy: SensitiveMediaPolicy
    private let localHost: String?
    private let progress: Double?
    private let isEdgeToEdge: Bool
    private let showsCounts: Bool
    private let onAction: (StatusRowAction) -> Void

    public init(
        status: Status, policy: SensitiveMediaPolicy, localHost: String?,
        progress: Double?, isEdgeToEdge: Bool = false,
        showsCounts: Bool = true,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.status = status
        self.policy = policy
        self.localHost = localHost
        self.progress = progress
        self.isEdgeToEdge = isEdgeToEdge
        self.showsCounts = showsCounts
        self.onAction = onAction
    }

    private var target: Status { status.displayed }

    public var body: some View {
        let attachment = target.mediaAttachments.first(where: { $0.isVideo })
        let isCovered = target.sensitive && !policy.allowsAutomaticReveal

        VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
            Button {
                onAction(.watch(status))
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    RemoteImage(
                        url: attachment?.displayImageURL,
                        blurhash: attachment?.blurhash,
                        accessibilityText: attachment?.description
                    )
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .overlay { if isCovered { Rectangle().fill(.ultraThinMaterial) } }

                    if let duration = attachment?.duration {
                        Text(Duration.seconds(duration), format: .time(pattern: .minuteSecond))
                            .font(AlohaType.micro.monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                .black, in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                            )
                            .foregroundStyle(.white)
                            .padding(AlohaMetrics.space2)
                    }

                    if let progress {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.black.opacity(0.4))
                                Rectangle()
                                    .fill(palette.accent)
                                    .frame(width: proxy.size.width * progress)
                            }
                        }
                        .frame(height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: isEdgeToEdge ? 0 : AlohaMetrics.cornerMedium,
                        style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Play \(VideoTitle.of(status))", comment: "Video card action"))

            HStack(alignment: .top, spacing: AlohaMetrics.space3) {
                Button {
                    onAction(.openProfile(target.account))
                } label: {
                    AvatarView(account: target.account, size: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text(
                        "Profile of \(target.account.bestDisplayName)",
                        comment: "Accessibility label for an avatar button"))

                VStack(alignment: .leading, spacing: 3) {
                    Text(VideoTitle.of(status))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    byline
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Menu {
                    StatusMenu(status: status, onAction: onAction)
                } label: {
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                        .foregroundStyle(palette.secondaryLabel)
                        // A bare symbol is an 18×6pt target; 44×44 is the floor.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel(Text("More actions", comment: "Video card action"))
            }
            .padding(.horizontal, isEdgeToEdge ? AlohaMetrics.space3 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { onAction(.watch(status)) }
    }

    /// "Alice · 12 favourites · 2d", the way a video app writes its byline.
    /// Built from `Text` pieces because the plural markup is resolved only
    /// when `Text` renders it.
    private var byline: Text {
        let name = Text(target.account.bestDisplayName)
        let age = Text(PostAge.short(target.createdAt))
        if showsCounts, target.favouritesCount > 0 {
            let count = Text(
                "^[\(target.favouritesCount) favourite](inflect: true)",
                comment: "Video byline count")
            return Text("\(name) · \(count) · \(age)", comment: "Video byline with a count")
        }
        return Text("\(name) · \(age)", comment: "Video byline")
    }
}
