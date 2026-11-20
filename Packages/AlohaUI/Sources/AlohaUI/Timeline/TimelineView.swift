// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaMedia
import AlohaModels
import AlohaStore
import SwiftUI
import TipKit

public struct TimelineView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.displayScale) private var displayScale
    @Environment(\.shellUsesTabBar) private var shellUsesTabBar
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.signInAgain) private var signInAgain
    /// The same scale `AvatarView` applies, for the prefetch's avatar size.
    @ScaledMetric(relativeTo: .body) private var typeScale: Double = 1

    @State private var model: TimelineModel
    @State private var listWidth: CGFloat = 0
    /// The selected post (`statusListNavigation`). `nil` until somebody
    /// clicks or presses `j`, so a timeline opens with nothing highlighted.
    @State private var selectedStatusID: String?
    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void
    /// Set once the first page has been scrolled to, so reopening a timeline
    /// does not pull the reader back to the post they had already left behind.
    /// Also set once the reader scrolls on their own: a marker that arrives
    /// from the server after that is not a reason to move them.
    @State private var didRestorePosition = false
    /// Whether this timeline is the one on screen, rather than under a pushed
    /// screen or in a tab not chosen. Only then does it refresh on a signal.
    @State private var isOnScreen = false
    /// Bumped by the new-posts pill; the list scrolls to the newest post.
    @State private var scrollToNewestRequests = 0
    /// Whether the scene went to the background since it was last active:
    /// the phase passes through `inactive` on the way back, so the previous
    /// phase alone cannot say.
    @State private var wasInBackground = false
    /// Where the VoiceOver rotors point: each post registers its row here.
    @Namespace private var rotorNamespace

    /// Where the reader was, when this screen is built over a model the shell
    /// kept (`FeedModels`): the list scrolls back there once, on appearing.
    @State private var resumeAnchorID: String?

    public init(
        key: TimelineKey, session: AccountSession,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.init(key: key, session: session, models: nil, onAction: onAction)
    }

    /// A feed the shell keeps the model of, so a shell built again — an
    /// iPhone Duo folding — finds its rows and its place where they were.
    init(
        key: TimelineKey, session: AccountSession, models: FeedModels?,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.session = session
        self.onAction = onAction
        let model = TimelineModel.kept(for: key, session: session, in: models)
        _model = State(initialValue: model)
        _resumeAnchorID = State(initialValue: model.rows.isEmpty ? nil : model.readingAnchorID)
    }

    public var body: some View {
        ZStack(alignment: .top) {
            list
            if model.pendingNewCount > 0 {
                newPostsPill
                    .transition(pillTransition)
            }
        }
        .animation(pillAnimation, value: model.pendingNewCount > 0)
        #if os(macOS)
            // A Mac has nothing to pull: a line under the toolbar says the
            // timeline is asking the server, and goes when it has answered.
            .overlay(alignment: .top) {
                if model.isRefreshing && !model.rows.isEmpty {
                    ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .tint(palette.accent)
                    .frame(height: 2)
                    .transition(.opacity)
                    .accessibilityLabel(Text("Refreshing", comment: "Timeline refresh progress"))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.isRefreshing)
        #endif
        .actionFeedbackToast()
        .background(palette.background.ignoresSafeArea())
        .task { await model.appear() }
        .refreshable { await model.refresh(revealingArrivals: true) }
        .onChange(of: session.lastPosted?.id) { _, _ in
            guard let posted = session.lastPosted else { return }
            Task { await model.insertOwn(posted) }
        }
        .onAppear { isOnScreen = true }
        .onDisappear {
            isOnScreen = false
            Task { await model.saveReadingMarker() }
        }
        // Nextcloud Social has no streaming, so nothing arrives unless asked
        // for: the sync engine says when the home timeline is due — a poll, or
        // a streamed post where there is a socket — and the timeline on
        // screen fetches. New posts still wait behind the pill unless the
        // reader is at the very top (docs/08 §2, docs/05 §3).
        .onChange(of: environment.sync.timelineRefreshRequests[session.id]) { _, _ in
            guard isOnScreen, followsHomeTimeline else { return }
            Task { await model.refresh() }
        }
        // Back in the foreground, the timeline catches up by itself rather
        // than waiting for a pull. Here rather than in the shell, so only the
        // timeline on screen fetches.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                wasInBackground = true
                guard isOnScreen else { return }
                Task { await model.saveReadingMarker() }
            case .active:
                // From the background — not merely from a glance at Control
                // Centre — it is a new visit, and the divider moves to where
                // the reader got to.
                let isNewVisit = wasInBackground
                wasInBackground = false
                guard isOnScreen else { return }
                Task {
                    if isNewVisit {
                        await model.beginNewVisit()
                        await model.refresh()
                        // After a while away the refresh opens a gap above
                        // where the reader left off; the posts just above
                        // it are fetched now, so scrolling up from there is
                        // continuous (docs/05 §3).
                        await model.catchUpAboveReader()
                    } else {
                        await model.refreshIfStale(olderThan: 30)
                    }
                }
            default:
                break
            }
        }
        // While it is on screen, the engine is told so — repeatedly, because
        // it trusts the word for five minutes and a reader stays longer.
        .task(id: isOnScreen && scenePhase == .active && followsHomeTimeline) {
            guard isOnScreen, scenePhase == .active, followsHomeTimeline else { return }
            while !Task.isCancelled {
                environment.sync.noteTimelineVisible(for: session.id)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// The home timeline and its media modes: what the sync engine's refresh
    /// signal is about.
    private var followsHomeTimeline: Bool { model.key.source == .home }

    /// The pill slides in from the top; with Reduce Motion it fades.
    private var pillTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    private var pillAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.72)
    }

    /// Scrolling the list for the reader is a jump, not a glide, with Reduce
    /// Motion on.
    private func scrollAnimation(_ duration: Double) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: duration)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            rows(horizontalInset: readingInset(for: listWidth))
                // Measured, not read: a GeometryReader around the whole list
                // re-evaluated it on every size pass for one number.
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: { width in
                    listWidth = width
                    reportPrefetchGeometry()
                }
                .onChange(of: displayScale) { _, _ in reportPrefetchGeometry() }
                // "Return to where I was": once the first page and the marker
                // are both in — in either order — scroll to the last-read post
                // rather than to the top. Off, the timeline opens at the newest
                // post, which is what a storefront expects.
                .onChange(of: model.rows.isEmpty) { _, _ in restorePosition(proxy) }
                .onChange(of: model.visitMarkerID) { _, _ in restorePosition(proxy) }
                .onAppear { resumeReading(proxy) }
                // Whether new posts may go straight in: only at the very top.
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y <= -geometry.contentInsets.top + 4
                } action: { _, isAtTop in
                    model.readerIsAtTop = isAtTop
                    if !isAtTop { didRestorePosition = true }
                }
                .onChange(of: scrollToNewestRequests) { _, _ in
                    // A turn later, so the list has the revealed rows to
                    // scroll to.
                    Task { @MainActor in
                        await Task.yield()
                        guard let newest = model.index.statusIDs.first else { return }
                        withAnimation(scrollAnimation(0.3)) {
                            proxy.scrollTo(newest, anchor: .top)
                        }
                    }
                }
                // Rows landed above the one the reader was on — a gap filled
                // from below — and it goes back to where it was, without
                // a glide that would read as the list moving by itself.
                .onChange(of: model.keepInPlace) { _, request in
                    guard let request else { return }
                    proxy.scrollTo(request.statusID, anchor: .top)
                }
        }
    }

    private func restorePosition(_ proxy: ScrollViewProxy) {
        guard
            !didRestorePosition, !model.rows.isEmpty,
            session.settings.restoreTimelinePosition,
            let markerID = model.visitMarkerID,
            model.index.status(id: markerID) != nil
        else { return }
        didRestorePosition = true
        // Already the newest post: the list is where it should be.
        guard model.index.statusIDs.first != markerID else { return }
        model.readerIsAtTop = false
        withAnimation(scrollAnimation(0.25)) {
            proxy.scrollTo(markerID, anchor: .top)
        }
    }

    /// Back to where the reader was when this screen was last built over the
    /// same model. Before the rows report themselves, which would otherwise
    /// make the top of the list the place to come back to.
    private func resumeReading(_ proxy: ScrollViewProxy) {
        guard let anchor = resumeAnchorID else { return }
        resumeAnchorID = nil
        guard model.index.status(id: anchor) != nil else { return }
        didRestorePosition = true
        guard model.index.statusIDs.first != anchor else { return }
        model.readerIsAtTop = false
        // A turn later, so the list has laid out the rows to scroll to.
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    /// What the rows will ask the image loader for, so the prefetch asks for
    /// the same sizes (`TimelineModel.prefetchRequests`).
    private func reportPrefetchGeometry() {
        let avatar = AvatarView.dimension(base: metrics.avatarSize, typeScale: typeScale)
        let inset = readingInset(for: listWidth)
        model.prefetchGeometry = PrefetchGeometry(
            contentWidth: max(1, listWidth - 2 * inset - avatar - AlohaMetrics.space3),
            avatarSize: avatar, scale: displayScale)
    }

    private func readingInset(for width: CGFloat) -> CGFloat {
        #if os(iOS)
            // The sidebar shell's reading column: iPad, and an unfolded
            // iPhone Duo.
            if !shellUsesTabBar {
                return ReadingMeasure.inset(forListWidth: width)
            }
        #endif
        return AlohaMetrics.space4
    }

    private func rows(horizontalInset: CGFloat) -> some View {
        SelectableList(selection: $selectedStatusID) {
            if session.needsReauthentication { reauthenticationBanner }
            if model.isOffline { offlineStrip }
            if let errorMessage = model.errorMessage { errorStrip(errorMessage) }

            // Announcements, "On this day" and the weekly recap sit above your
            // own home feed and nowhere else.
            if model.key.mode == .home, model.key.source == .home {
                HomeTimelineExtras(session: session, onAction: onAction)
                if !model.rows.isEmpty, hasSwipeActions { swipeTip }
            }

            // Skeleton rows until the first fetch is back, and the empty
            // state only once one has come back with nothing: before, the
            // moment between the view appearing and the refresh starting
            // said "Nothing here yet" to everybody.
            if model.rows.isEmpty {
                if model.isLoadingFirstPage {
                    ForEach(0..<3, id: \.self) { index in
                        SkeletonRow(hasMedia: index == 1)
                            .listRowInsets(
                                EdgeInsets(
                                    top: 0, leading: horizontalInset, bottom: 0,
                                    trailing: horizontalInset)
                            )
                            .listRowBackground(palette.background)
                            .listRowSeparator(.hidden)
                    }
                } else if model.showsEmptyState {
                    emptyState
                }
            }

            ForEach(model.rows) { row in
                switch row {
                case .status(let status):
                    StatusRow(
                        status: status,
                        policy: session.settings.sensitiveMediaPolicy,
                        localHost: session.snapshot.instanceHost,
                        filterWarning: model.filterWarning(for: status),
                        canReact: session.capabilities.emojiReactions,
                        isOwn: status.displayed.account.id == session.snapshot.serverAccountID,
                        showsCounts: session.settings.showPopularityCounts,
                        onAction: onAction
                    )
                    // Only the rows whose post changed redraw (`StatusRow: Equatable`).
                    .equatable()
                    .listRowInsets(
                        EdgeInsets(
                            top: AlohaMetrics.space1, leading: horizontalInset,
                            bottom: AlohaMetrics.space1,
                            trailing: horizontalInset)
                    )
                    .statusListRow(status.id, ground: palette.background)
                    .listRowSeparator(.hidden)
                    .id(status.id)
                    .statusRowInteractions(status, session: session, onAction: onAction)
                    .accessibilityRotorEntry(id: status.id, in: rotorNamespace)
                    .readingSignal(
                        status,
                        context: InterestSignal.Context(key: model.key),
                        session: session
                    )
                    .onAppear {
                        Task { await model.prefetchOlder(near: status.id) }
                        model.prefetchMedia(around: row.id)
                        // Which posts are on screen, so the topmost can be
                        // saved as where the reader got to.
                        model.noteRow(status.id, isVisible: true)
                    }
                    .onDisappear { model.noteRow(status.id, isVisible: false) }

                case .gap(let id):
                    gapRow(id: id)

                case .caughtUpDivider:
                    caughtUpDivider
                }
            }

            if model.canLoadOlder || model.isPagingOlder {
                OlderPostsFooter(isLoading: model.isPagingOlder) {
                    Task { await model.loadOlder() }
                }
                .listRowBackground(palette.background)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .environment(\.filterVerdicts, model.verdicts)
        // A rotor to move post by post, and one to land on the posts that
        // carry links, without walking every action inside each row
        // (docs/12 §3).
        .accessibilityRotor(Text("Posts", comment: "VoiceOver rotor name")) {
            ForEach(model.index.statuses) { status in
                AccessibilityRotorEntry(
                    Text(
                        "\(status.displayed.account.bestDisplayName), \(PostAge.spoken(status.displayed.createdAt))",
                        comment: "VoiceOver rotor entry for a post: author, then age"),
                    id: status.id, in: rotorNamespace)
            }
        }
        .accessibilityRotor(Text("Links", comment: "VoiceOver rotor name")) {
            // One entry per link, in reading order, named for where it goes.
            ForEach(model.index.linkEntries) { entry in
                AccessibilityRotorEntry(
                    Text(verbatim: entry.label), id: entry.statusID, in: rotorNamespace)
            }
        }
        .statusListNavigation(
            selection: $selectedStatusID,
            ids: model.index.statusIDs,
            status: { [index = model.index] id in index.status(id: id) },
            onAction: onAction,
            refresh: { await model.refresh(revealingArrivals: true) })
    }

    private var hasSwipeActions: Bool {
        session.settings.leadingSwipeAction != .none
            || session.settings.trailingSwipeAction != .none
    }

    /// Swiping is invisible until somebody is told, so the home feed says it
    /// once, inline, where the posts are.
    private var swipeTip: some View {
        TipView(SwipeActionsTip())
            .listRowBackground(palette.background)
            .listRowSeparator(.hidden)
    }

    /// A hole between two fetched ranges, never closed silently.
    private func gapRow(id: String) -> some View {
        Button {
            Task { await model.fillGap(id: id) }
        } label: {
            HStack(spacing: AlohaMetrics.space2) {
                Spacer()
                Image(systemName: AlohaSymbol.gap)
                Text("Load the posts in between", comment: "Timeline gap row")
                Spacer()
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(palette.accent)
            .padding(.vertical, AlohaMetrics.space3)
        }
        .buttonStyle(.plain)
        .listRowBackground(palette.surfaceRaised)
        .unifiedGlass(.subtle)
    }

    /// Where the reader left off last visit: everything above it is new.
    private var caughtUpDivider: some View {
        HStack(spacing: AlohaMetrics.space2) {
            Spacer()
            VStack(spacing: AlohaMetrics.space1) {
                Rectangle()
                    .fill(palette.separator)
                    .frame(height: 1)
                Text("You're caught up", comment: "Timeline caught up divider")
                    .font(AlohaType.micro)
                    .foregroundStyle(palette.tertiaryLabel)
            }
            Spacer()
        }
        .padding(.vertical, AlohaMetrics.space3)
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
    }

    /// New content never moves what the person is reading. Tapping the pill
    /// shows it and takes the reader to the newest post (docs/05 §3).
    private var newPostsPill: some View {
        Button {
            withAnimation(scrollAnimation(0.2)) { model.revealPendingRows() }
            scrollToNewestRequests += 1
        } label: {
            HStack(spacing: AlohaMetrics.space2) {
                Image(systemName: "arrow.up")
                Text(
                    "^[\(model.pendingNewCount) new post](inflect: true)", comment: "New posts pill"
                )
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(palette.onAccent)
            .padding(.horizontal, AlohaMetrics.space4)
            .padding(.vertical, AlohaMetrics.space2)
            // Glass in the server's colour, floating over the posts like the
            // bars above and below it, instead of a painted capsule with a
            // drop shadow of its own. Under Reduce Transparency the system
            // makes the glass opaque, and the accent still carries it.
            .alohaGlassEffect(.regular.tint(palette.accent).interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, AlohaMetrics.space2)
    }

    // MARK: - Non-content states

    private var reauthenticationBanner: some View {
        HStack(spacing: AlohaMetrics.space3) {
            Image(systemName: AlohaSymbol.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your sign-in has expired", comment: "Re-auth banner title")
                    .font(.footnote.weight(.semibold))
                // Nothing is deleted: the cache stays, and so does the account.
                Text(
                    "Your posts are still here. Sign in again to refresh.",
                    comment: "Re-auth banner detail"
                )
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
            }
            Spacer()
            // The banner said what to do and offered no way to do it; the
            // sheet this opens goes straight to the account's own server.
            Button {
                signInAgain(session.id)
            } label: {
                Text("Sign in", comment: "Re-auth banner action")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityHint(
                Text(
                    "Opens your server's sign-in page", comment: "Re-auth banner action hint"))
        }
        .padding(AlohaMetrics.space3)
        .background(palette.surfaceRaised)
        .unifiedGlass(.regular)
        .listRowInsets(EdgeInsets())
        .listRowBackground(palette.background)
    }

    private var offlineStrip: some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.offline)
            Text("Offline — showing what's cached", comment: "Offline strip")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(palette.secondaryLabel)
        .padding(.vertical, AlohaMetrics.space2)
        .listRowBackground(palette.background)
    }

    private func errorStrip(_ message: String) -> some View {
        AlohaErrorStrip(message: message) {
            Task { await model.refresh() }
        }
        .listRowBackground(palette.background)
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: model.key.mode.symbolName,
            title: Text(emptyTitle),
            message: Text(emptyDetail)
        ) {
            // A timeline with nothing in it has one useful next step.
            NavigationLink(value: Route.explore) {
                Text("Find people to follow", comment: "Empty timeline action")
            }
        }
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
    }

    private var emptyTitle: String {
        switch model.key.mode {
        case .home: String(localized: "Nothing here yet", comment: "Empty timeline")
        case .photos: String(localized: "No photos yet", comment: "Empty Photos mode")
        case .video: String(localized: "No videos yet", comment: "Empty Video mode")
        case .shorts: String(localized: "No shorts yet", comment: "Empty Shorts mode")
        case .news: String(localized: "No links yet", comment: "Empty News mode")
        case .audio: String(localized: "No audio yet", comment: "Empty Audio mode")
        }
    }

    /// Where the server cannot narrow, say so once rather than letting results
    /// look mysteriously thin (docs/06 §2).
    private var emptyDetail: String {
        let serverFilters = TimelineFilters.forMode(
            model.key.mode, capabilities: session.capabilities)
        if model.key.mode != .home && serverFilters.isEmpty {
            return String(
                localized: "This server can't filter by media type, so results may be sparse.",
                comment: "Empty mode explanation on a server without the narrowings")
        }
        return String(
            localized: "Follow a few people and this will fill up.",
            comment: "Empty timeline explanation")
    }
}

/// A link the links rotor offers, pointing at the post that carries it.
struct LinkRotorEntry: Identifiable, Hashable {
    let id: String
    let statusID: String
    let label: String

    /// Host and path, which is what a person needs to choose a link by ear;
    /// the scheme and query are noise read aloud.
    static func label(for url: URL) -> String {
        let host = url.host() ?? url.absoluteString
        let path = url.path()
        return path.isEmpty || path == "/" ? host : host + path
    }
}
