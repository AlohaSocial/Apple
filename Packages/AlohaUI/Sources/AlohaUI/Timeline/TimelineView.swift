// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaMedia
import AlohaModels
import AlohaStore
import SwiftUI

public struct TimelineView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics
    @Environment(AppEnvironment.self) private var environment

    @State private var model: TimelineModel
    /// The post the keyboard is on. `nil` until somebody presses `j`, so a
    /// timeline opened with a mouse shows no ring it did not earn.
    @State private var focusedStatusID: String?
    @State private var isShowingShortcuts = false
    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void
    /// Set once the first page has been scrolled to, so reopening a timeline
    /// does not pull the reader back to the post they had already left behind.
    @State private var didRestorePosition = false

    public init(
        key: TimelineKey, session: AccountSession,
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.session = session
        self.onAction = onAction
        _model = State(initialValue: TimelineModel(key: key, session: session))
    }

    public var body: some View {
        ZStack(alignment: .top) {
            list
            if model.pendingNewCount > 0 {
                newPostsPill
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: model.pendingNewCount > 0)
        .background(palette.background.ignoresSafeArea())
        .timelineKeyboard(
            focusedID: $focusedStatusID,
            isShowingShortcuts: $isShowingShortcuts,
            ids: model.rows.compactMap { row in
                if case .status(let status) = row { return status.id } else { return nil }
            },
            status: { id in
                model.rows.compactMap { row -> Status? in
                    if case .status(let status) = row, status.id == id { return status }
                    return nil
                }.first
            },
            onAction: onAction
        )
        .sheet(isPresented: $isShowingShortcuts) { ShortcutHelpView() }
        .task { await model.appear() }
        .refreshable { await model.refresh() }
        .onChange(of: session.lastPosted?.id) { _, _ in
            guard let posted = session.lastPosted else { return }
            Task { await model.insertOwn(posted) }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            rows
                // "Return to where I was": once the first page is in, scroll to
                // the last-read post rather than to the top. Off, the timeline
                // opens at the newest post, which is what a storefront expects.
                .onChange(of: model.rows.isEmpty) { _, isEmpty in
                    guard
                        !isEmpty, !didRestorePosition,
                        session.settings.restoreTimelinePosition,
                        let markerID = model.caughtUpMarkerID,
                        model.rows.contains(where: { $0.id == markerID })
                    else { return }
                    didRestorePosition = true
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(markerID, anchor: .top)
                    }
                }
                .onChange(of: focusedStatusID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
        }
    }

    private var rows: some View {
        List {
            if session.needsReauthentication { reauthenticationBanner }
            if model.isOffline { offlineStrip }
            if let errorMessage = model.errorMessage { errorStrip(errorMessage) }

            // Announcements, "On this day" and the weekly recap sit above your
            // own home feed and nowhere else.
            if model.key.mode == .home, model.key.source == .home {
                HomeTimelineExtras(session: session, onAction: onAction)
            }

            if model.rows.isEmpty {
                if model.isRefreshing {
                    ForEach(0..<3, id: \.self) { index in
                        SkeletonRow(hasMedia: index == 1)
                            .listRowInsets(EdgeInsets(top: 0, leading: metrics.space4, bottom: 0, trailing: metrics.space4))
                            .listRowBackground(palette.background)
                            .listRowSeparator(.hidden)
                    }
                } else {
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
                    .listRowInsets(EdgeInsets(top: metrics.space1, leading: metrics.space4, bottom: metrics.space1, trailing: metrics.space4))
                    .listRowBackground(palette.background)
                    .listRowSeparator(.hidden)
                    .id(status.id)
                    .overlay(alignment: .leading) {
                        if focusedStatusID == status.id {
                            Capsule()
                                .fill(palette.accent)
                                .frame(width: 3)
                                .padding(.vertical, metrics.space2)
                                .padding(.leading, -8)
                        }
                    }
                    .onAppear {
                        if row.id == model.rows.last?.id {
                            Task { await model.loadOlder() }
                        }
                        model.prefetchMedia(around: row.id)
                    }

                case .gap(let id):
                    gapRow(id: id)

                case .caughtUpDivider(let after):
                    caughtUpDivider(after: after)
                        .onAppear {
                            // The divider sits below the last-read post: when
                            // it becomes visible the reader has passed it, so
                            // the marker moves to the post that follows.
                            guard let idx = model.rows.firstIndex(where: { $0.id == "caughtUp-\(after)" }),
                                idx + 1 < model.rows.count,
                                case .status(let next) = model.rows[idx + 1]
                            else { return }
                            model.advanceCaughtUpMarker(to: next.id)
                        }
                }
            }

            if model.isPagingOlder {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(palette.background)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(palette.background)
    }

    /// A hole between two fetched ranges, never closed silently.
    private func gapRow(id: String) -> some View {
        Button {
            Task { await model.fillGap(id: id) }
        } label: {
            HStack(spacing: metrics.space2) {
                Spacer()
                Image(systemName: AlohaSymbol.gap)
                Text("Load the posts in between", comment: "Timeline gap row")
                Spacer()
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(palette.accent)
            .padding(.vertical, metrics.space3)
        }
        .buttonStyle(.plain)
        .listRowBackground(palette.surfaceRaised)
        .unifiedGlass(.subtle)
    }

    /// A visual divider marking where the previous session ended.
    private func caughtUpDivider(after statusID: String) -> some View {
        HStack(spacing: metrics.space2) {
            Spacer()
            VStack(spacing: metrics.space1) {
                Rectangle()
                    .fill(palette.separator)
                    .frame(height: 1)
                Text("You're caught up", comment: "Timeline caught up divider")
                    .font(AlohaType.micro)
                    .foregroundStyle(palette.tertiaryLabel)
            }
            Spacer()
        }
        .padding(.vertical, metrics.space3)
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
    }

    /// A visual divider marking where the previous session ended.
    private func caughtUpDivider(after statusID: String) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Spacer()
            VStack(spacing: AlohaMetrics.space1) {
                Rectangle()
                    .fill(palette.separator)
                    .frame(height: 1)
                Text("You're caught up", comment: "Timeline caught up divider")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.tertiaryLabel)
            }
            Spacer()
        }
        .padding(.vertical, AlohaMetrics.space3)
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
    }

    /// New content never moves what the person is reading.
    private var newPostsPill: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { model.revealPendingRows() }
        } label: {
            HStack(spacing: metrics.space2) {
                Image(systemName: "arrow.up")
                Text(
                    "^[\(model.pendingNewCount) new post](inflect: true)", comment: "New posts pill"
                )
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(palette.onAccent)
            .padding(.horizontal, metrics.space4)
            .padding(.vertical, metrics.space2)
            .background(palette.accent, in: Capsule())
            .shadow(color: palette.accent.opacity(0.3), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.top, metrics.space2)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Non-content states

    private var reauthenticationBanner: some View {
        HStack(spacing: metrics.space3) {
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
        }
        .padding(metrics.space3)
        .background(palette.surfaceRaised)
        .unifiedGlass(.regular)
        .listRowInsets(EdgeInsets())
        .listRowBackground(palette.background)
    }

    private var offlineStrip: some View {
        HStack(spacing: metrics.space2) {
            Image(systemName: AlohaSymbol.offline)
            Text("Offline — showing what's cached", comment: "Offline strip")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(palette.secondaryLabel)
        .padding(.vertical, metrics.space2)
        .listRowBackground(palette.background)
    }

    private func errorStrip(_ message: String) -> some View {
        HStack(spacing: metrics.space2) {
            Image(systemName: AlohaSymbol.warning)
            Text(message).font(.caption)
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                Text("Retry", comment: "Error strip action")
            }
            .font(.caption.weight(.semibold))
        }
        .foregroundStyle(palette.destructive)
        .padding(.vertical, metrics.space2)
        .unifiedGlass(.regular)
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
