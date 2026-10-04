// SPDX-License-Identifier: MIT

import AVKit
import AlohaDesign
import AlohaHTML
import AlohaMedia
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Full-screen vertical pager, one short per page, edge to edge — laid out
/// the way a short-video app lays it out: a Following / For You switch at
/// the top, a rail of big glyphs with counts down the trailing edge, the
/// handle and caption at the foot, and a hairline of playback progress along
/// the very bottom.
///
/// Autoplay is always on here — a vertical short-video feed that does not play
/// is not the feature. What adapts under Low Power or Low Data is the preload
/// depth, never the decision (docs/06 §4).
public struct ShortsView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    /// Following is your home timeline; For You is everything the server sees.
    enum Feed: String, CaseIterable, Identifiable {
        case following, forYou
        var id: String { rawValue }
        var source: TimelineSource {
            switch self {
            case .following: .home
            case .forYou: .federated
            }
        }
        var title: Text {
            switch self {
            case .following: Text("Following", comment: "Shorts feed")
            case .forYou: Text("For You", comment: "Shorts feed")
            }
        }
    }

    @State private var feed: Feed = .forYou
    @State private var model: TimelineModel
    @State private var currentID: String?
    @State private var preloader = NextVideoPreloader()
    @AppStorage("aloha.shorts.muted") private var isMuted = true
    @State private var isPaused = false
    @State private var progress: Double = 0
    @State private var hearted: String?
    @State private var expandedCaption: String?

    public init(session: AccountSession, onAction: @escaping (StatusRowAction) -> Void) {
        self.session = session
        self.onAction = onAction
        _model = State(
            initialValue: TimelineModel(
                key: TimelineKey(mode: .shorts, source: Feed.forYou.source), session: session))
    }

    private var shorts: [Status] {
        // `only_video` is not implemented consistently by all compatible
        // servers. Never render an image or audio status as a Short.
        model.rows.compactMap(\.status).filter { status in
            status.displayed.mediaAttachments.contains(where: { $0.isVideo })
        }
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                if shorts.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(shorts) { status in
                                page(
                                    status, isCurrent: status.id == currentID,
                                    insets: proxy.safeAreaInsets
                                )
                                .containerRelativeFrame([.horizontal, .vertical])
                                .id(status.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $currentID)
                    .scrollIndicators(.hidden)
                    .ignoresSafeArea()
                }

                topBar
                    .padding(.top, proxy.safeAreaInsets.top)
                    .frame(maxHeight: .infinity, alignment: .top)

                progressBar
                    .padding(.bottom, proxy.safeAreaInsets.bottom)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .ignoresSafeArea()
        }
        .background { Color.black.ignoresSafeArea() }
        .task { await start() }
        .task(id: "\(currentID ?? ""): \(preloader.allowsPrefetch):\(shorts.count)") {
            guard let currentID, let index = shorts.firstIndex(where: { $0.id == currentID })
            else { preloader.cancel(); return }
            guard shorts.indices.contains(index + 1) else {
                preloader.retainCurrent(statusID: shorts[index].displayed.id, accountID: session.id)
                return
            }
            await preloader.prepare(status: shorts[index + 1], keeping: shorts[index].displayed.id,
                session: session)
        }
        .onDisappear { preloader.cancel() }
        .onChange(of: feed) { _, newFeed in
            model = TimelineModel(
                key: TimelineKey(mode: .shorts, source: newFeed.source), session: session)
            currentID = nil
            progress = 0
            Task { await start() }
        }
        .onChange(of: currentID) { _, newValue in
            progress = 0
            // Page ahead well before the end so the feed never stalls.
            guard let newValue, let position = shorts.firstIndex(where: { $0.id == newValue })
            else { return }
            if position >= shorts.count - 3 {
                Task { await model.loadOlder() }
            }
        }
    }

    private func start() async {
        await model.appear()
        if currentID == nil { currentID = shorts.first?.id }
    }

    // MARK: - Chrome

    private var topBar: some View {
        ZStack {
            HStack(spacing: AlohaMetrics.space5) {
                ForEach(Feed.allCases) { option in
                    Button {
                        if reduceMotion {
                            feed = option
                        } else {
                            withAnimation(.snappy) { feed = option }
                        }
                    } label: {
                        VStack(spacing: 5) {
                            option.title
                                .font(.body.weight(feed == option ? .bold : .semibold))
                                .foregroundStyle(.white.opacity(feed == option ? 1 : 0.65))
                            Capsule()
                                .fill(.white)
                                .frame(width: 28, height: 3)
                                .opacity(feed == option ? 1 : 0)
                        }
                        .shadow(color: .black.opacity(0.4), radius: 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(feed == option ? [.isButton, .isSelected] : .isButton)
                }
            }

            HStack {
                Button {
                    isMuted.toggle()
                } label: {
                    Image(systemName: isMuted ? AlohaSymbol.mute : AlohaSymbol.unmute)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .shadow(color: .black.opacity(0.4), radius: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isMuted
                        ? Text("Unmute", comment: "Shorts action")
                        : Text("Mute", comment: "Shorts action"))

                Spacer()

                NavigationLink(value: Route.search(query: nil)) {
                    Image(systemName: AlohaSymbol.search)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .shadow(color: .black.opacity(0.4), radius: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Search", comment: "Toolbar button"))
            }
        }
        .padding(.horizontal, AlohaMetrics.space2)
        .padding(.top, AlohaMetrics.space1)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.25))
                Rectangle()
                    .fill(.white)
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Page

    private func page(_ status: Status, isCurrent: Bool, insets: EdgeInsets) -> some View {
        ZStack {
            if let attachment = status.displayed.mediaAttachments.first(where: { $0.isVideo }) {
                ShortPlayer(
                    preloader: preloader,
                    attachment: attachment,
                    statusID: status.displayed.id,
                    apiBase: session.capabilities.apiBase,
                    session: session,
                    isCurrent: isCurrent,
                    isMuted: isMuted,
                    isPaused: isPaused,
                    loops: session.settings.loopShorts,
                    // Sensitive shorts are not autoplayed under blur or hide —
                    // a consent decision, and it stands.
                    isCovered: status.displayed.sensitive
                        && !session.settings.sensitiveMediaPolicy.allowsAutomaticReveal,
                    autoplay: session.settings.autoplayVideo,
                    progress: isCurrent ? $progress : .constant(0),
                    onWatched: { position, duration in
                        await report(status: status, position: position, duration: duration)
                    })
            }

            // Without scrims, white overlay text vanishes over a bright frame.
            LinearGradient(
                colors: [.black.opacity(0.55), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 160)
            .frame(maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)

            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 260)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            overlay(status)
                .padding(.top, insets.top)
                .padding(.bottom, insets.bottom)

            if isPaused && isCurrent {
                Image(systemName: AlohaSymbol.play)
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(radius: 8)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if hearted == status.id {
                Image(systemName: "heart.fill")
                    .font(.system(size: 110))
                    .foregroundStyle(palette.favourite)
                    .shadow(radius: 12)
                    .transition(
                        reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity)
                    )
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { heart(status) }
        // Holding pauses, as it does everywhere else of this shape; letting go
        // resumes. Every gesture here has a button equivalent on the rail.
        .onLongPressGesture(
            minimumDuration: 0.25,
            pressing: { pressing in
                withAnimation(.easeOut(duration: 0.15)) { isPaused = pressing }
            }, perform: {}
        )
        .sensoryFeedback(.success, trigger: hearted)
    }

    private func heart(_ status: Status) {
        if !status.displayed.favourited { onAction(.favourite(status)) }
        // The heart is the whole reward for the gesture; without it a
        // double tap feels like it did nothing.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { hearted = status.id }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.25)) { hearted = nil }
        }
    }

    private func overlay(_ status: Status) -> some View {
        let displayed = status.displayed
        return VStack(alignment: .leading) {
            Spacer()

            HStack(alignment: .bottom, spacing: AlohaMetrics.space3) {
                caption(status)
                Spacer(minLength: 0)
                rail(status)
            }
            .padding(.leading, AlohaMetrics.space3)
            .padding(.trailing, AlohaMetrics.space2)
            .padding(.bottom, AlohaMetrics.space4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            Text(
                "\(displayed.account.bestDisplayName): \(plainText(displayed))",
                comment: "Accessibility label for a short"))
    }

    private func caption(_ status: Status) -> some View {
        let displayed = status.displayed
        let text = plainText(displayed)
        let isExpanded = expandedCaption == status.id
        // Text-sized buttons still get a 44pt-tall target; the frames overlap
        // the gaps between lines rather than pushing them apart.
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                onAction(.openProfile(displayed.account))
            } label: {
                Text(displayed.account.qualifiedHandle(localHost: session.snapshot.instanceHost))
                    .font(.subheadline.weight(.bold))
                    .frame(minHeight: 44, alignment: .bottomLeading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !text.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        expandedCaption = isExpanded ? nil : status.id
                    }
                } label: {
                    Text(text)
                        .font(.footnote)
                        .lineLimit(isExpanded ? 12 : 2)
                        .multilineTextAlignment(.leading)
                        .padding(.vertical, AlohaMetrics.space1)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Expands the caption", comment: "Accessibility hint"))
            }

            HStack(spacing: AlohaMetrics.space1) {
                Image(systemName: "music.note")
                    .font(.caption2)
                Text(
                    "Original audio · \(displayed.account.bestDisplayName)",
                    comment: "Shorts sound line"
                )
                .font(.caption)
                .lineLimit(1)
            }
            .padding(.top, AlohaMetrics.space1)
            .accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.5), radius: 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rail(_ status: Status) -> some View {
        let displayed = status.displayed
        return VStack(spacing: AlohaMetrics.space4) {
            Button {
                onAction(.openProfile(displayed.account))
            } label: {
                AvatarView(account: displayed.account, size: 46)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    .overlay(alignment: .bottom) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(palette.onAccent)
                            .frame(width: 18, height: 18)
                            .background(palette.accent, in: Circle())
                            .offset(y: 9)
                    }
                    .padding(.bottom, AlohaMetrics.space2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                Text(
                    "Profile of \(displayed.account.bestDisplayName)",
                    comment: "Accessibility label for an avatar button"))

            railButton(
                symbol: displayed.favourited ? AlohaSymbol.favouriteFilled : AlohaSymbol.favourite,
                tint: displayed.favourited ? palette.favourite : .white,
                count: displayed.favouritesCount,
                label: Text("Favourite", comment: "Shorts action")
            ) { onAction(.favourite(status)) }

            railButton(
                symbol: AlohaSymbol.reply, tint: .white, count: displayed.repliesCount,
                label: Text("Reply", comment: "Shorts action")
            ) { onAction(.open(status)) }

            railButton(
                symbol: AlohaSymbol.boost, tint: displayed.reblogged ? palette.boost : .white,
                count: displayed.reblogsCount,
                label: Text("Boost", comment: "Shorts action")
            ) { onAction(.boost(status)) }

            railButton(
                symbol: displayed.bookmarked ? AlohaSymbol.bookmarkFilled : AlohaSymbol.bookmark,
                tint: displayed.bookmarked ? palette.bookmark : .white,
                count: nil,
                label: Text("Bookmark", comment: "Shorts action")
            ) { onAction(.bookmark(status)) }

            railButton(
                symbol: AlohaSymbol.share, tint: .white, count: nil,
                label: Text("Share", comment: "Shorts action")
            ) { onAction(.share(status)) }

            Menu {
                StatusMenu(status: status, onAction: onAction)
            } label: {
                Image(systemName: AlohaSymbol.more)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 40)
                    .contentShape(Rectangle())
                    .shadow(color: .black.opacity(0.4), radius: 3)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(Text("More actions", comment: "Shorts action"))
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.55), value: displayed.favourited)
    }

    private func railButton(
        symbol: String, tint: Color, count: Int?, label: Text, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(tint)
                if let count, count > 0 {
                    Text(count, format: .number.notation(.compactName))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 48)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .shadow(color: .black.opacity(0.4), radius: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var emptyState: some View {
        VStack(spacing: AlohaMetrics.space3) {
            Image(systemName: FeedMode.shorts.symbolName)
                .font(.largeTitle)
            Text("No shorts yet", comment: "Empty Shorts mode")
                .font(.headline)
            if feed == .following {
                Text(
                    "Nobody you follow has posted a short. Try For You.",
                    comment: "Shorts empty state on the following feed"
                )
                .font(.footnote)
                .multilineTextAlignment(.center)
            } else if !session.capabilities.onlyVideoFilter {
                Text(
                    "This server can't filter by media type, so this may take a moment to fill.",
                    comment: "Shorts empty state on a server without only_video"
                )
                .font(.footnote)
                .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func plainText(_ status: Status) -> String {
        StatusHTMLParser().plainText(status.content).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reported per reader, never federated, never shown to anybody else.
    private func report(status: Status, position: Double, duration: Double) async {
        guard session.capabilities.watchPositions,
            WatchPositionRules.shouldReport(position: position, duration: duration)
        else { return }

        try? await session.supportStore.recordWatchPosition(
            accountID: session.id, statusID: status.displayed.id,
            position: position, duration: duration)
        _ = try? await session.client.send(
            Endpoint.video.reportWatched(
                status.displayed.id, position: position, duration: duration))
    }
}

/// One short's player. At most three live instances exist across the pager.
struct ShortPlayer: View {
    let preloader: NextVideoPreloader
    let attachment: MediaAttachment
    let statusID: String
    let apiBase: URL
    let session: AccountSession?
    let isCurrent: Bool
    let isMuted: Bool
    let isPaused: Bool
    let loops: Bool
    let isCovered: Bool
    let autoplay: Bool
    @Binding var progress: Double
    let onWatched: (Double, Double) async -> Void

    @State private var player: AVPlayer?
    @State private var isReady = false
    @State private var looper: Any?
    @State private var ticker: Any?
    @State private var watcher: Task<Void, Never>?

    var body: some View {
        ZStack {
            if isCovered {
                RemoteImage(
                    url: attachment.previewURL, blurhash: attachment.blurhash, contentMode: .fill
                )
                .overlay(.ultraThinMaterial)
                .overlay {
                    VStack(spacing: AlohaMetrics.space2) {
                        Image(systemName: AlohaSymbol.sensitive).font(.title)
                        Text("Sensitive content", comment: "Shorts cover")
                    }
                    .foregroundStyle(.white)
                }
            } else {
                if let player, isReady {
                    PlayerSurface(player: player, showsControls: false)
                } else {
                    RemoteImage(
                        url: attachment.previewURL, blurhash: attachment.blurhash, contentMode: .fill)
                }
            }
        }
        .task(id: isCurrent) { await manage() }
        .onChange(of: isMuted) { _, muted in player?.isMuted = muted }
        .onChange(of: isPaused) { _, paused in
            guard isCurrent, autoplay else { return }
            if paused { player?.pause() } else { player?.play() }
        }
        .onDisappear { teardown() }
    }

    private func manage() async {
        guard isCurrent, !isCovered else {
            teardown()
            return
        }
        teardown()

        if let session, let (prepared, item) = preloader.take(key: NextVideoPreloader.key(
            accountID: session.id, statusID: statusID, attachmentID: attachment.id)) {
            isReady = item.status == .readyToPlay
            item.preferredPeakBitRate = 0
            item.preferredForwardBufferDuration = 0
            watch(item)
            await start(prepared, item: item)
            return
        }

        let sources = VideoSourceResolver.sources(
            for: attachment, statusID: statusID, apiBase: apiBase,
            isRemote: VideoSourceResolver.isRemote(attachment))

        // Every rung is judged before anything is shown: a pager full of
        // players bound to items that never became playable is a pager full
        // of black rectangles, and the poster behind each one is the honest
        // answer until a source actually works.
        for source in sources {
            guard !Task.isCancelled, isCurrent else { return }
            let headers = await session?.client.mediaRequestHeaders(for: source.url) ?? [:]
            switch await PlaybackReadiness.open(url: source.url, headers: headers) {
            case .playable(let newPlayer, let item, let ready):
                guard !Task.isCancelled, isCurrent else { return }
                isReady = ready
                watch(item)
                await start(newPlayer, item: item)
                return
            case .rejected(let reason):
                PlaybackLog.logger.error("short rung rejected: \(reason, privacy: .public)")
            }
        }
    }

    /// Lifts the poster the moment there is a frame behind it — a rung can
    /// open before it has parsed far enough to draw — and drops the player if
    /// the file collapses after having opened.
    private func watch(_ item: AVPlayerItem) {
        watcher = Task { @MainActor in
            for await status in PlaybackReadiness.statuses(item) {
                guard !Task.isCancelled else { return }
                switch status {
                case .readyToPlay:
                    isReady = true
                case .failed:
                    PlaybackLog.logger.error(
                        "short failed after opening: \(item.error?.localizedDescription ?? "unknown", privacy: .public)")
                    teardown()
                    return
                default:
                    break
                }
            }
        }
    }

    private func start(_ newPlayer: AVPlayer, item: AVPlayerItem) async {
        newPlayer.isMuted = isMuted
        newPlayer.actionAtItemEnd = loops ? .none : .pause
        player = newPlayer

        if loops {
            looper = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
            ) { _ in
                newPlayer.seek(to: .zero)
                newPlayer.play()
            }
        }

        // Four ticks a second is enough for a hairline to read as motion.
        ticker = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { time in
            let duration = item.duration.seconds
            guard duration.isFinite, duration > 0 else { return }
            // Delivered on the main queue, which is the main actor.
            MainActor.assumeIsolated { progress = time.seconds / duration }
        }

        if autoplay, !isPaused { newPlayer.play() }

        // Report as it goes, coalesced well inside the server's 600-a-minute.
        while !Task.isCancelled, isCurrent, player != nil {
            try? await Task.sleep(for: .seconds(WatchPositionRules.reportInterval))
            let position = newPlayer.currentTime().seconds
            let duration = item.duration.seconds
            if position.isFinite, duration.isFinite, duration > 0 {
                await onWatched(position, duration)
            }
        }
    }

    private func teardown() {
        watcher?.cancel()
        watcher = nil
        if let ticker { player?.removeTimeObserver(ticker) }
        ticker = nil
        player?.pause()
        player = nil
        isReady = false
        if let looper { NotificationCenter.default.removeObserver(looper) }
        looper = nil
    }
}
