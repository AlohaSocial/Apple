// SPDX-License-Identifier: MIT

import AVKit
import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The photo app people already know: a stories rail, then one post after
/// another — header, picture, action row, likes, caption. A square grid is a
/// tap away for browsing; the toggle is remembered.
public struct PhotosModeView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.mediaTransition) private var mediaTransition

    private let session: AccountSession
    private let source: TimelineSource
    private let onAction: (StatusRowAction) -> Void

    @State private var model: TimelineModel
    // Grid is the default, per docs/06 §5: a 3-column square grid is what a
    // photo mode opens on, and the feed is the slower, deliberate reading of
    // the same posts. Remembered per device.
    @AppStorage("aloha.photosLayout") private var layout: Layout = .grid
    @State private var stories: [Story] = []
    @State private var playingStoriesFrom: Int?

    enum Layout: String, CaseIterable {
        case grid, feed
    }

    public init(
        session: AccountSession, source: TimelineSource,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.session = session
        self.source = source
        self.onAction = onAction
        _model = State(
            initialValue: TimelineModel(
                key: TimelineKey(mode: .photos, source: source), session: session))
    }

    public var body: some View {
        Group {
            switch layout {
            case .feed: feed
            case .grid: grid
            }
        }
        .background(palette.background)
        // The display format sits over the content rather than in the toolbar:
        // a toolbar item is four taps from the pictures and competes with the
        // title for the only slot there, while the one control this screen has
        // belongs where the thumb already is.
        .safeAreaInset(edge: .top, spacing: 0) {
            formatBar
                .padding(.vertical, AlohaMetrics.space2)
                .background(palette.background.opacity(0.85))
        }
        .task {
            await model.appear()
            await loadStories()
        }
        .refreshable {
            await model.refresh()
            await loadStories()
        }
        .fullScreenCoverIfAvailable(
            item: Binding(
                get: { playingStoriesFrom.map { StoryStart(index: $0) } },
                set: { playingStoriesFrom = $0?.index })
        ) { start in
            StoryPlayer(stories: stories, startIndex: start.index, session: session)
        }
    }

    /// The display format, as a two-state glass switcher rather than a plain
    /// segmented control: an accent pill slides behind the chosen one, and each
    /// state carries its own label, so "which layout am I on" never depends on
    /// telling two icons apart.
    private var formatBar: some View {
        HStack(spacing: AlohaMetrics.space2) {
            Spacer(minLength: 0)

            HStack(spacing: 0) {
                ForEach(PhotosModeView.Layout.allCases, id: \.rawValue) { option in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            layout = option
                        }
                    } label: {
                        Label {
                            Text(title(for: option))
                        } icon: {
                            Image(systemName: symbolName(for: option))
                        }
                        .labelStyle(.iconOnly)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(
                            layout == option ? palette.onAccent : palette.secondaryLabel)
                        .padding(.horizontal, AlohaMetrics.space3)
                        .padding(.vertical, AlohaMetrics.space2)
                        .frame(minWidth: 44, minHeight: 44)
                        .background {
                            if layout == option {
                                Capsule().fill(palette.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(title(for: option)))
                    .accessibilityAddTraits(layout == option ? .isSelected : [])
                }
            }
            .unifiedGlass(.regular, in: Capsule())

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AlohaMetrics.space3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Layout", comment: "Photos layout picker"))
    }

    private func title(for layout: PhotosModeView.Layout) -> String {
        switch layout {
        case .feed: String(localized: "Feed", comment: "Photos layout")
        case .grid: String(localized: "Grid", comment: "Photos layout")
        }
    }

    private func symbolName(for layout: PhotosModeView.Layout) -> String {
        switch layout {
        case .feed: "rectangle.grid.1x2"
        case .grid: "square.grid.3x3"
        }
    }

    /// Mastodon's home timeline ignores `only_media`, so a text-only status
    /// can arrive here; a blank tile is never the right way to show one.
    private var statuses: [Status] {
        model.rows.compactMap(\.status).filter { !$0.displayed.mediaAttachments.isEmpty }
    }

    // MARK: - Feed

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if session.capabilities.stories {
                    storyCarousel
                    Divider()
                }

                ForEach(statuses) { status in
                    PhotoPostCard(
                        status: status,
                        policy: session.settings.sensitiveMediaPolicy,
                        localHost: session.snapshot.instanceHost,
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
        }
    }

    // MARK: - Grid

    static let gutter: Double = 1.5

    private var grid: some View {
        ScrollView {
            if session.capabilities.stories { storyCarousel }

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: Self.gutter), count: 3),
                spacing: Self.gutter
            ) {
                ForEach(statuses) { status in
                    cell(status)
                        .aspectRatio(1, contentMode: .fit)
                        .onAppear {
                            if status.id == statuses.last?.id {
                                Task { await model.loadOlder() }
                            }
                        }
                }
            }

            if statuses.isEmpty && !model.isRefreshing { emptyState }
        }
    }

    private func cell(_ status: Status) -> some View {
        let attachments = status.displayed.mediaAttachments
        let first = attachments.first
        let isCovered =
            status.displayed.sensitive
            && !session.settings.sensitiveMediaPolicy.allowsAutomaticReveal

        return Button {
            onAction(.openMedia(status: status.displayed, index: 0))
        } label: {
            ZStack(alignment: .topTrailing) {
                RemoteImage(
                    url: first?.displayImageURL,
                    blurhash: first?.blurhash,
                    accessibilityText: first?.description
                )
                .aspectRatio(1, contentMode: .fill)
                .overlay {
                    if isCovered { Rectangle().fill(.ultraThinMaterial) }
                }

                if attachments.count > 1 {
                    Image(systemName: "square.on.square.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(6)
                        .shadow(radius: 2)
                        .accessibilityLabel(
                            Text(
                                "^[\(attachments.count) photo](inflect: true)",
                                comment: "Multi-image badge"))
                } else if first?.type.isPlayable == true {
                    Image(systemName: AlohaSymbol.play)
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
        .mediaTransitionSource(id: first?.id ?? status.id, in: mediaTransition)
    }

    // MARK: - Stories

    /// Yours first, then everybody else's in the order the server ranked them.
    private var ownStories: [Story] {
        stories.filter { $0.account.id == session.snapshot.serverAccountID }
    }

    private var othersStories: [Story] {
        stories.filter { $0.account.id != session.snapshot.serverAccountID }
    }

    private var storyCarousel: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AlohaMetrics.space3) {
                StoryComposerTile(
                    session: session, ownStories: ownStories,
                    onPlay: {
                        if let first = ownStories.first,
                            let index = stories.firstIndex(where: { $0.id == first.id })
                        {
                            playingStoriesFrom = index
                        }
                    },
                    onPosted: { Task { await loadStories() } })

                ForEach(othersStories) { story in
                    Button {
                        if let index = stories.firstIndex(where: { $0.id == story.id }) {
                            playingStoriesFrom = index
                        }
                    } label: {
                        VStack(spacing: AlohaMetrics.space1) {
                            AvatarView(account: story.account, size: 60)
                                .padding(3)
                                .overlay(
                                    Circle().strokeBorder(
                                        story.seen
                                            ? AnyShapeStyle(palette.separator)
                                            : AnyShapeStyle(storyRing),
                                        lineWidth: story.seen ? 1 : 2.5))
                            Text(story.account.username)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(maxWidth: 66)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        story.seen
                            ? Text(
                                "Story from \(story.account.bestDisplayName)",
                                comment: "Story rail tile")
                            : Text(
                                "New story from \(story.account.bestDisplayName)",
                                comment: "Story rail tile"))
                }
            }
            .padding(.horizontal, AlohaMetrics.space3)
            .padding(.vertical, AlohaMetrics.space2)
        }
        .scrollIndicators(.hidden)
    }

    /// The unseen ring is a sweep through the accent rather than a flat line.
    private var storyRing: AngularGradient {
        AngularGradient(
            colors: [palette.accent, palette.favourite, palette.accent],
            center: .center)
    }

    /// Expect this to be sparse. Pixelfed only fans stories out to instances it
    /// has identified as Pixelfed, so stories from Pixelfed accounts do not
    /// arrive here at all — an empty carousel is not an error (docs/06 §6).
    ///
    /// The rail is shown once there is a server that serves stories at all,
    /// so the composer tile is there before anybody has posted one.
    private func loadStories() async {
        guard session.capabilities.stories else { return }
        let carousel =
            (try? await session.client.decode(StoryCarousel.self, from: Endpoint.stories.carousel))
            ?? StoryCarousel()
        let mine = session.snapshot.serverAccountID
        var live = (carousel.own + carousel.others).filter { $0.isLive() }
        // Only one run of each story, whichever list the server put it in.
        var seen = Set<String>()
        live = live.filter { seen.insert($0.id).inserted }
        stories = live.filter { $0.account.id == mine } + live.filter { $0.account.id != mine }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Text("No photos yet", comment: "Empty Photos mode")
        } description: {
            if !session.capabilities.onlyMediaFilter {
                Text(
                    "This server can't filter by media type, so results may be sparse.",
                    comment: "Empty mode explanation")
            } else {
                Text("Follow some people who post pictures.", comment: "Empty Photos detail")
            }
        }
        .padding(.top, AlohaMetrics.space6)
    }
}

// MARK: - Post card

/// One post in the photo feed: who, the picture, the actions, the caption.
///
/// The picture is the point, so it runs edge to edge and is cropped to the
/// band a photo app allows — never taller than 4:5, never wider than 1.91:1 —
/// so every post lands at a predictable height and the feed scrolls evenly.
public struct PhotoPostCard: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.mediaTransition) private var mediaTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let status: Status
    private let policy: SensitiveMediaPolicy
    private let localHost: String?
    private let showsCounts: Bool
    private let onAction: (StatusRowAction) -> Void

    @State private var page = 0
    @State private var isRevealed = false
    @State private var isCaptionExpanded = false
    @State private var isHearting = false

    public init(
        status: Status, policy: SensitiveMediaPolicy, localHost: String?,
        showsCounts: Bool = true,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.status = status
        self.policy = policy
        self.localHost = localHost
        self.showsCounts = showsCounts
        self.onAction = onAction
    }

    private var displayed: Status { status.displayed }
    private var attachments: [MediaAttachment] { displayed.mediaAttachments }
    private var isCovered: Bool {
        displayed.sensitive && !policy.allowsAutomaticReveal && !isRevealed
    }

    /// Portrait posts stop at 4:5, landscape at 1.91:1.
    private var aspect: Double {
        min(max(attachments.first?.displayAspectRatio ?? 1, 0.8), 1.91)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            media
            actionRow
            details
        }
        .padding(.bottom, AlohaMetrics.space4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photo.\(displayed.id)")
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: AlohaMetrics.space2) {
            Button {
                onAction(.openProfile(displayed.account))
            } label: {
                HStack(spacing: AlohaMetrics.space2) {
                    AvatarView(account: displayed.account, size: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(displayed.account.bestDisplayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.label)
                            .lineLimit(1)
                        Text(displayed.account.qualifiedHandle(localHost: localHost))
                            .font(.caption2)
                            .foregroundStyle(palette.tertiaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                Text(
                    "Profile of \(displayed.account.bestDisplayName)",
                    comment: "Accessibility label for an avatar button"))

            Spacer(minLength: AlohaMetrics.space2)

            if let booster = status.booster {
                Label {
                    Text(booster.bestDisplayName)
                } icon: {
                    Image(systemName: AlohaSymbol.boost)
                }
                .font(.caption2)
                .foregroundStyle(palette.tertiaryLabel)
                .lineLimit(1)
            }

            Menu {
                StatusMenu(status: status, onAction: onAction)
            } label: {
                Image(systemName: AlohaSymbol.more)
                    .foregroundStyle(palette.label)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(Text("More actions", comment: "Status action"))
        }
        .padding(.leading, AlohaMetrics.space3)
        .padding(.trailing, AlohaMetrics.space1)
        .padding(.vertical, AlohaMetrics.space1)
    }

    // MARK: Media

    private var media: some View {
        ZStack {
            if attachments.count > 1 {
                TabView(selection: $page) {
                    ForEach(Array(attachments.enumerated()), id: \.element.id) {
                        offset, attachment in
                        picture(attachment).tag(offset)
                    }
                }
                #if os(iOS)
                    .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
            } else if let first = attachments.first {
                picture(first)
            }

            if isCovered { cover }

            if isHearting {
                Image(systemName: AlohaSymbol.favouriteFilled)
                    .font(.system(size: 88))
                    .foregroundStyle(.white)
                    .shadow(radius: 10)
                    .transition(
                        reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity)
                    )
                    .allowsHitTesting(false)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .topTrailing) {
            if attachments.count > 1 {
                Text(verbatim: "\(page + 1)/\(attachments.count)")
                    .font(AlohaType.micro.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(AlohaMetrics.space3)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) {
            if attachments.count > 1 { pageDots }
        }
        .contentShape(Rectangle())
        // Double must be declared before single, so the single tap waits for
        // the double to fail rather than firing on the first of two.
        .onTapGesture(count: 2) { heart() }
        .onTapGesture {
            if isCovered {
                withAnimation { isRevealed = true }
            } else {
                onAction(.openMedia(status: displayed, index: page))
            }
        }
        .sensoryFeedback(.success, trigger: isHearting) { _, new in new }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Opens the media viewer", comment: "Accessibility hint"))
        .accessibilityAction(named: Text("Favourite", comment: "Accessibility action")) { heart() }
        .mediaTransitionSource(id: attachments.first?.id ?? displayed.id, in: mediaTransition)
    }

    private func picture(_ attachment: MediaAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            RemoteImage(
                url: attachment.displayImageURL,
                blurhash: attachment.blurhash,
                contentMode: .fill,
                accessibilityText: attachment.description)

            if attachment.type.isPlayable {
                Image(systemName: AlohaSymbol.play)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.5), in: Circle())
                    .padding(AlohaMetrics.space3)
                    .accessibilityHidden(true)
            }
        }
    }

    private var cover: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: AlohaMetrics.space2) {
                Image(systemName: AlohaSymbol.sensitive).font(.title2)
                Text("Sensitive content", comment: "Covered media title")
                    .font(.subheadline.weight(.semibold))
                Text("Tap to show", comment: "Covered media hint")
                    .font(.caption)
            }
            .foregroundStyle(palette.label)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 4) {
            ForEach(attachments.indices, id: \.self) { index in
                Circle()
                    .fill(index == page ? palette.accent : .white.opacity(0.7))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(6)
        .background(.black.opacity(0.25), in: Capsule())
        .padding(.bottom, AlohaMetrics.space2)
        .accessibilityHidden(true)
    }

    private func heart() {
        guard !displayed.favourited else { return }
        onAction(.favourite(status))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { isHearting = true }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.25)) { isHearting = false }
        }
    }

    // MARK: Actions

    private var actionRow: some View {
        HStack(spacing: 0) {
            actionButton(
                symbol: displayed.favourited ? AlohaSymbol.favouriteFilled : AlohaSymbol.favourite,
                tint: displayed.favourited ? palette.favourite : palette.label,
                label: Text("Favourite", comment: "Status action")
            ) { onAction(.favourite(status)) }

            actionButton(
                symbol: "bubble.right", tint: palette.label,
                label: Text("Reply", comment: "Status action")
            ) { onAction(.reply(status)) }

            actionButton(
                symbol: AlohaSymbol.boost,
                tint: displayed.reblogged ? palette.boost : palette.label,
                label: Text("Boost", comment: "Status action")
            ) { onAction(.boost(status)) }

            actionButton(
                symbol: "paperplane", tint: palette.label,
                label: Text("Share", comment: "Status action")
            ) { onAction(.share(status)) }

            Spacer(minLength: 0)

            actionButton(
                symbol: displayed.bookmarked ? AlohaSymbol.bookmarkFilled : AlohaSymbol.bookmark,
                tint: displayed.bookmarked ? palette.bookmark : palette.label,
                label: Text("Bookmark", comment: "Status action")
            ) { onAction(.bookmark(status)) }
        }
        .padding(.horizontal, AlohaMetrics.space1)
        .padding(.top, AlohaMetrics.space1)
        .animation(.spring(response: 0.32, dampingFraction: 0.55), value: displayed.favourited)
    }

    private func actionButton(
        symbol: String, tint: Color, label: Text, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
            if showsCounts, displayed.favouritesCount > 0 {
                Text(
                    "^[\(displayed.favouritesCount) favourite](inflect: true)",
                    comment: "Photo post like count"
                )
                .font(.subheadline.weight(.semibold))
            }

            if displayed.hasContentWarning {
                Text(displayed.spoilerText)
                    .font(.subheadline.weight(.medium))
            } else if !caption.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayed.account.bestDisplayName)
                        .font(.subheadline.weight(.semibold))
                    RichTextView(status: status, lineLimit: isCaptionExpanded ? nil : 2) { link in
                        onAction(.followLink(link))
                    }
                    if !isCaptionExpanded && caption.count > 90 {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { isCaptionExpanded = true }
                        } label: {
                            Text("more", comment: "Expand a truncated caption")
                                .font(.subheadline)
                                .foregroundStyle(palette.tertiaryLabel)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if displayed.repliesCount > 0 {
                Button {
                    onAction(.open(status))
                } label: {
                    Text(
                        showsCounts
                            ? "View all ^[\(displayed.repliesCount) reply](inflect: true)"
                            : "View all replies",
                        comment: "Photo post reply count link"
                    )
                    .font(.subheadline)
                    .foregroundStyle(palette.tertiaryLabel)
                }
                .buttonStyle(.plain)
            }

            Text(displayed.createdAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(palette.tertiaryLabel)
        }
        .padding(.horizontal, AlohaMetrics.space3)
        .padding(.top, AlohaMetrics.space1)
    }

    private var caption: String {
        StatusHTMLParser().plainText(displayed.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct StoryStart: Identifiable, Hashable {
    let index: Int
    var id: Int { index }
}

/// Tap-forward, tap-back, hold-to-pause, swipe-down to dismiss.
///
/// Under somebody else's story: eight emoji to react with and a reply field
/// (a reply reaches the poster as a direct message). Under your own: who
/// watched, who reacted, and a way to take it down.
public struct StoryPlayer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    private let onDeleted: (Story) -> Void

    @State private var stories: [Story]
    @State private var index: Int
    @State private var elapsed: Double = 0
    @State private var isHolding = false
    @State private var reply = ""
    @State private var isSending = false
    @State private var floatingReaction: String?
    @State private var notice: String?
    @State private var listSheet: ListSheet?
    @State private var isConfirmingDelete = false
    @FocusState private var isReplying: Bool

    enum ListSheet: Identifiable {
        case viewers(Story), reactions(Story)
        var id: String {
            switch self {
            case .viewers(let story): "viewers.\(story.id)"
            case .reactions(let story): "reactions.\(story.id)"
            }
        }
    }

    public init(
        stories: [Story], startIndex: Int, session: AccountSession,
        onDeleted: @escaping (Story) -> Void = { _ in }
    ) {
        _stories = State(initialValue: stories)
        self.session = session
        self.onDeleted = onDeleted
        _index = State(initialValue: startIndex)
    }

    private var current: Story? { stories.indices.contains(index) ? stories[index] : nil }
    private var isPaused: Bool { isHolding || isReplying || listSheet != nil || isConfirmingDelete }

    private func isOwn(_ story: Story) -> Bool {
        story.account.id == session.snapshot.serverAccountID
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let current {
                media(current)

                VStack(spacing: 0) {
                    progressBars
                    header(current)
                    Spacer()
                    if let caption = current.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AlohaMetrics.space4)
                            .padding(.bottom, AlohaMetrics.space3)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                    }
                    if isOwn(current) { ownControls(current) } else { audienceControls(current) }
                }

                if let floatingReaction {
                    Text(floatingReaction)
                        .font(.system(size: 110))
                        .shadow(radius: 12)
                        .transition(
                            reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity)
                        )
                        .allowsHitTesting(false)
                }

                if let notice {
                    Text(notice)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AlohaMetrics.space4)
                        .padding(.vertical, AlohaMetrics.space2)
                        .background(.black.opacity(0.6), in: Capsule())
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            if isReplying { isReplying = false } else { advance(forward: location.x > 120) }
        }
        .onLongPressGesture(minimumDuration: 0.2, pressing: { isHolding = $0 }, perform: {})
        .gesture(
            DragGesture().onEnded { value in
                if value.translation.height > 100 { dismiss() }
            }
        )
        .task(id: index) { await play() }
        .sheet(item: $listSheet) { sheet in
            switch sheet {
            case .viewers(let story): StoryViewersSheet(story: story, session: session)
            case .reactions(let story): StoryReactionsSheet(story: story, session: session)
            }
        }
        .alert(
            Text("Delete this story?", comment: "Story delete confirmation"),
            isPresented: $isConfirmingDelete
        ) {
            Button(role: .destructive) {
                Task { await deleteCurrent() }
            } label: {
                Text("Delete", comment: "Story delete action")
            }
            Button(role: .cancel) {
            } label: {
                Text("Cancel", comment: "Story delete action")
            }
        } message: {
            Text(
                "It goes away for everybody, now rather than tomorrow.",
                comment: "Story delete detail")
        }
    }

    @ViewBuilder
    private func media(_ story: Story) -> some View {
        if story.type.isPlayable, let url = story.url {
            StoryVideoSurface(
                url: url, preview: story.previewURL, isPaused: isPaused, session: session)
                .ignoresSafeArea()
        } else {
            RemoteImage(url: story.url, contentMode: .fit)
                .ignoresSafeArea()
        }
    }

    private var progressBars: some View {
        HStack(spacing: 3) {
            ForEach(stories.indices, id: \.self) { position in
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.3))
                        Capsule()
                            .fill(.white)
                            .frame(width: proxy.size.width * fraction(for: position))
                    }
                }
                .frame(height: 2.5)
            }
        }
        .padding(.horizontal, AlohaMetrics.space3)
        .padding(.top, AlohaMetrics.space2)
        .accessibilityHidden(true)
    }

    private func fraction(for position: Int) -> Double {
        guard let current else { return 0 }
        if position < index { return 1 }
        if position > index { return 0 }
        return min(1, elapsed / max(0.1, current.duration))
    }

    private func header(_ story: Story) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            AvatarView(account: story.account, size: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(
                    isOwn(story)
                        ? String(localized: "Your story", comment: "Story player own title")
                        : story.account.bestDisplayName
                )
                .font(.footnote.weight(.semibold))
                Text(PostAge.short(story.publishedAt))
                    .font(.caption2)
                    .opacity(0.8)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close", comment: "Story action"))
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.5), radius: 2)
        .padding(.horizontal, AlohaMetrics.space3)
        .padding(.top, AlohaMetrics.space1)
    }

    // MARK: - Audience

    private func audienceControls(_ story: Story) -> some View {
        VStack(spacing: AlohaMetrics.space2) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(StoryComposerSheet.emojiStickers, id: \.self) { emoji in
                        Button {
                            Task { await react(emoji, to: story) }
                        } label: {
                            Text(emoji)
                                .font(.system(size: 30))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isSending)
                        .accessibilityLabel(Text("React with \(emoji)", comment: "Story reaction"))
                    }
                }
                .padding(.horizontal, AlohaMetrics.space2)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: AlohaMetrics.space2) {
                TextField(
                    String(localized: "Reply…", comment: "Story reply prompt"),
                    text: $reply
                )
                .textFieldStyle(.plain)
                .focused($isReplying)
                .foregroundStyle(.white)
                .padding(.horizontal, AlohaMetrics.space3)
                .padding(.vertical, AlohaMetrics.space2)
                .frame(minHeight: 44)
                .background(.white.opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                .onSubmit { Task { await sendReply(to: story) } }
                .accessibilityLabel(Text("Reply to story", comment: "Story reply label"))

                Button {
                    Task { await sendReply(to: story) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(canSendReply ? .white : .white.opacity(0.4))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(!canSendReply)
                .accessibilityLabel(Text("Send reply", comment: "Story reply action"))
            }
            .padding(.horizontal, AlohaMetrics.space3)
        }
        .padding(.bottom, AlohaMetrics.space3)
    }

    private var canSendReply: Bool {
        !isSending && !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func react(_ emoji: String, to story: Story) async {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { floatingReaction = emoji }
        do {
            _ = try await session.client.send(Endpoint.storyExtras.react(story.id, reaction: emoji))
        } catch {
            await session.handle(error)
            await show(
                String(localized: "That reaction didn't send.", comment: "Story reaction failure"))
        }
        try? await Task.sleep(for: .milliseconds(700))
        withAnimation(.easeOut(duration: 0.25)) { floatingReaction = nil }
    }

    private func sendReply(to story: Story) async {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            _ = try await session.client.send(Endpoint.storyExtras.comment(story.id, caption: text))
            reply = ""
            isReplying = false
            await show(String(localized: "Sent as a message", comment: "Story reply sent"))
        } catch {
            await session.handle(error)
            await show(String(localized: "That reply didn't send.", comment: "Story reply failure"))
        }
    }

    // MARK: - Own

    private func ownControls(_ story: Story) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Button {
                listSheet = .viewers(story)
            } label: {
                Label {
                    if let views = story.viewCount, session.settings.showPopularityCounts {
                        Text("Seen by \(views)", comment: "Story viewers button")
                    } else {
                        Text("Seen by", comment: "Story viewers button")
                    }
                } icon: {
                    Image(systemName: AlohaSymbol.reveal)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AlohaMetrics.space3)
            .frame(minHeight: 44)
            .background(.white.opacity(0.18), in: Capsule())

            Button {
                listSheet = .reactions(story)
            } label: {
                Label {
                    Text("Reactions", comment: "Story reactions button")
                } icon: {
                    Image(systemName: "face.smiling")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AlohaMetrics.space3)
            .frame(minHeight: 44)
            .background(.white.opacity(0.18), in: Capsule())

            Spacer()

            Button {
                isConfirmingDelete = true
            } label: {
                Image(systemName: AlohaSymbol.delete)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Delete story", comment: "Story action"))
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, AlohaMetrics.space3)
        .padding(.bottom, AlohaMetrics.space3)
    }

    private func deleteCurrent() async {
        guard let story = current else { return }
        do {
            do {
                _ = try await session.client.send(Endpoint.stories.delete(story.id))
            } catch APIError.notFound {
                // Pixelfed's own name for the same thing. A server that serves
                // its story routes and not Mastodon's answers here instead, and
                // a 404 on the first must not read as "could not be deleted".
                _ = try await session.client.send(Endpoint.storyExtras.selfExpire(story.id))
            }
            onDeleted(story)
            stories.remove(at: index)
            if stories.isEmpty {
                dismiss()
            } else {
                index = min(index, stories.count - 1)
                elapsed = 0
            }
        } catch {
            await session.handle(error)
            await show(
                String(
                    localized: "That story couldn't be deleted.", comment: "Story delete failure"))
        }
    }

    // MARK: - Playback

    private func show(_ text: String) async {
        withAnimation(.easeOut(duration: 0.2)) { notice = text }
        try? await Task.sleep(for: .seconds(1.6))
        withAnimation(.easeOut(duration: 0.25)) { notice = nil }
    }

    private func play() async {
        guard let current else { return }
        elapsed = 0

        // Idempotent, so a repeat is a no-op rather than a second view — and
        // never for your own, which would count you as your own audience.
        if !current.seen, !isOwn(current) {
            _ = try? await session.client.send(Endpoint.stories.markSeen(current.id))
        }

        while elapsed < current.duration, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            if !isPaused { elapsed += 0.05 }
        }
        guard !Task.isCancelled else { return }
        advance(forward: true)
    }

    private func advance(forward: Bool) {
        if forward {
            if index + 1 < stories.count { index += 1 } else { dismiss() }
        } else {
            if index > 0 { index -= 1 }
        }
    }
}

/// A video story: plays on appear, pauses while held, no controls.
struct StoryVideoSurface: View {
    let url: URL
    let preview: URL?
    let isPaused: Bool
    let session: AccountSession

    @State private var player: AVPlayer?
    @State private var isReady = false
    @State private var watcher: Task<Void, Never>?

    var body: some View {
        ZStack {
            if let player, isReady {
                PlayerSurface(player: player, showsControls: false)
            } else {
                // The story's own still, held until there is a frame behind
                // it. A black rectangle in this window is the thing people
                // read as "the video is broken".
                // Never hand the video bytes to the image loader when the
                // server omitted a poster frame.
                RemoteImage(url: preview, contentMode: .fit)
            }
        }
        .task(id: url) {
            player = nil
            isReady = false
            watcher?.cancel()
            watcher = nil
            let headers = await session.client.mediaRequestHeaders(for: url)
            switch await PlaybackReadiness.open(url: url, headers: headers) {
            case .playable(let newPlayer, let item, let ready):
                player = newPlayer
                isReady = ready
                if !isPaused { newPlayer.play() }
                watcher = Task { @MainActor in
                    for await status in PlaybackReadiness.statuses(item) {
                        guard !Task.isCancelled else { return }
                        if status == .readyToPlay { isReady = true }
                    }
                }
            case .rejected(let reason):
                PlaybackLog.logger.error("story rung rejected: \(reason, privacy: .public)")
            }
        }
        .onChange(of: isPaused) { _, paused in
            if paused { player?.pause() } else { player?.play() }
        }
        .onDisappear {
            watcher?.cancel()
            watcher = nil
            player?.pause()
            player = nil
            isReady = false
        }
    }
}
