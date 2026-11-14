// SPDX-License-Identifier: MIT

import AlohaHTML
import AlohaMedia
import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import OSLog
import Observation

/// Drives one timeline: cache-first paint, anchored paging, gap handling, and
/// the client-side filtering a server without the narrowings forces.
@MainActor
@Observable
public final class TimelineModel {
    /// Assigned once per change, through `commit`: every assignment rebuilds
    /// the index over up to five hundred rows and redraws the list.
    public private(set) var rows: [TimelineRow] = [] {
        didSet { index = TimelineIndex(rows: rows, webLinks: webLinks) }
    }
    /// What the view needs from `rows` besides the rows themselves — ids in
    /// order, a lookup by id, the rotor entries — derived once per change of
    /// `rows`, not on every evaluation of the view's body.
    private(set) var index = TimelineIndex(rows: [], webLinks: [:])
    public private(set) var isRefreshing = false
    public private(set) var isPagingOlder = false
    public private(set) var errorMessage: String?
    public private(set) var isOffline = false
    /// New content never moves the scroll position; it waits behind this
    /// (docs/05 §3).
    public private(set) var pendingNewCount = 0
    private var pendingRows: [TimelineRow] = []

    public let key: TimelineKey
    private let session: AccountSession
    private var nextCursor: URL?
    private var refreshTask: Task<Void, Never>?
    private var lastRefresh: Date?
    /// Set by a gap on a timeline that pages only by link: the next refresh
    /// reloads from the top instead of merging (see `fillGap`).
    @ObservationIgnored private var replacesCacheOnNextRefresh = false
    @ObservationIgnored private var statusUpdates: NotificationSubscription?
    @ObservationIgnored private var statusRemovals: NotificationSubscription?
    /// When the server last confirmed an interaction with a status, per id.
    /// A page fetched *before* that moment carries the older copy and must
    /// not overwrite the confirmation again (see `performRefresh`).
    @ObservationIgnored private var confirmations: [String: Date] = [:]
    /// Statuses with an optimistic copy on screen whose server answer has
    /// not arrived, and since when. Every page is older than that answer, so
    /// none may overwrite the copy (`TimelineStatusUpdate.isProvisional`).
    @ObservationIgnored private var inFlight: [String: Date] = [:]

    /// Where the reader left off when this visit began: the newest home post
    /// they had seen. The timeline opens there and the "caught up" divider
    /// sits above it, and both stay put for the visit while the saved marker
    /// moves on underneath (docs/08 §7).
    public private(set) var visitMarkerID: String?
    /// The home marker as saved, locally and on the server. Only ever moves
    /// to a newer post.
    @ObservationIgnored private var savedMarkerID: String?
    /// Whether the reader's own scrolling has saved a marker this visit, after
    /// which a marker read back late must not move the divider under them.
    @ObservationIgnored private var markerMovedThisVisit = false
    /// The posts on screen, reported by the rows as they come and go, so the
    /// topmost of them can be saved as the marker.
    @ObservationIgnored private var visibleStatusIDs: Set<String> = []
    @ObservationIgnored private var markerSaveTask: Task<Void, Never>?
    @ObservationIgnored private var lastMarkerSave = Date.distantPast
    /// Whether the list is scrolled to its very top, reported by the view.
    /// Only there may new posts go straight into the list: anywhere else they
    /// would move what the reader is looking at, so they wait behind the
    /// pill (docs/05 §3). A list starts at the top.
    @ObservationIgnored public var readerIsAtTop = true
    /// The web links in each post, by row id, for the VoiceOver links rotor
    /// (docs/12 §3). Filled as pages arrive, from the parse the rich-text
    /// cache does anyway, because the view cannot parse inside its body.
    public private(set) var webLinks: [String: [URL]] = [:] {
        didSet { index = TimelineIndex(rows: rows, webLinks: webLinks) }
    }

    /// How the rows are laid out, reported by the view, so a prefetch asks
    /// for the sizes the rows will ask for and lands in the same cache entry.
    @ObservationIgnored public var prefetchGeometry = PrefetchGeometry()

    /// Each status's filter verdict, decided once per content rather than on
    /// every evaluation of the row — the same object every other list of
    /// posts filters with, in this timeline's context.
    let verdicts: FilterVerdicts

    private let logger = Logger(subsystem: "social.aloha.app", category: "timeline")

    public init(key: TimelineKey, session: AccountSession) {
        self.key = key
        self.session = session
        verdicts = FilterVerdicts(context: FilterVerdicts.context(for: key.source))
        statusUpdates = Self.observeStatusUpdates { [weak self] update in
            guard let self, update.accountID == self.session.id else { return }
            let now = Date()
            Self.pruneConfirmations(&self.confirmations, now: now)
            Self.pruneConfirmations(&self.inFlight, now: now)
            self.confirmations[update.status.id] = now
            if update.isProvisional {
                self.inFlight[update.status.id] = now
            } else {
                self.inFlight[update.status.id] = nil
            }
            self.rows = Self.replacing(update.status, in: self.rows)
            self.pendingRows = Self.replacing(update.status, in: self.pendingRows)
        }
        // A post deleted, or its author blocked or muted, leaves the rows
        // now rather than at the next refresh — and leaves the rows held
        // behind the new-posts pill, which would otherwise bring it back.
        statusRemovals = StatusRemovals.observe { [weak self] removal in
            guard let self, removal.accountID == self.session.id else { return }
            let kept = Self.removing(removal, from: self.rows)
            if kept.count != self.rows.count { self.commit(kept) }
            guard !self.pendingRows.isEmpty else { return }
            self.pendingRows = Self.removing(removal, from: self.pendingRows)
            let known = Set(self.rows.map(\.id))
            self.pendingNewCount =
                self.pendingRows.compactMap(\.status).filter { !known.contains($0.id) }.count
        }

        // Load the "caught up" marker for the home timeline.
        if tracksReadingPosition {
            Task { await loadCaughtUpMarker() }
        }
    }

    /// Only your own home feed has a marker; every other list opens at the
    /// top and keeps no reading position.
    private var tracksReadingPosition: Bool { key.mode == .home && key.source == .home }

    /// Loads the home marker: the local one first, so the divider is there
    /// at once, then the server's, which is how another device's reading
    /// reaches this one. The marker was written to the server but only ever
    /// read back locally, so cross-device sync went one way (docs/08 §7).
    private func loadCaughtUpMarker() async {
        var local: String?
        do {
            local = try await session.supportStore.marker(
                accountID: session.id, timeline: "home")
        } catch {
            logger.debug(
                "could not load home marker: \(String(describing: error), privacy: .public)")
        }
        if let local, !local.isEmpty { adoptLoadedMarker(local) }

        let server = try? await session.client.decode(
            MarkerSet.self, from: Endpoint.markers.read
        ).home?.lastReadID
        guard let newest = Self.newestMarker(local: savedMarkerID, server: server),
            newest != savedMarkerID
        else { return }
        _ = try? await session.supportStore.advanceMarker(
            accountID: session.id, timeline: "home", to: newest)
        adoptLoadedMarker(newest)
    }

    /// The marker that is further along. Neither copy may move the other
    /// backwards — the same rule the store and the server keep.
    nonisolated static func newestMarker(local: String?, server: String?) -> String? {
        let local = local.flatMap { $0.isEmpty ? nil : $0 }
        let server = server.flatMap { $0.isEmpty ? nil : $0 }
        switch (local, server) {
        case (nil, nil): return nil
        case (let only?, nil), (nil, let only?): return only
        case (let local?, let server?):
            return SupportStore.isNewer(server, than: local) ? server : local
        }
    }

    /// A marker read back from the store or the server. It becomes where this
    /// visit opens and where its divider sits — unless the reader has already
    /// scrolled on, in which case it only moves the saved marker forward.
    private func adoptLoadedMarker(_ id: String) {
        if let saved = savedMarkerID, !SupportStore.isNewer(id, than: saved) { return }
        savedMarkerID = id
        guard !markerMovedThisVisit else { return }
        visitMarkerID = id
        commit(rows)
    }

    /// The app came back from the background: what the reader saw last time
    /// is now where they left off, and another device may have read further.
    public func beginNewVisit() async {
        guard tracksReadingPosition else { return }
        markerSaveTask?.cancel()
        await saveReadingMarker()
        markerMovedThisVisit = false
        if let savedMarkerID, savedMarkerID != visitMarkerID {
            visitMarkerID = savedMarkerID
            commit(rows)
        }
        await loadCaughtUpMarker()
    }

    // MARK: - Reading position

    /// A post row came on screen, or went. The marker is saved a moment after
    /// the scrolling stops, so a fling past fifty posts writes once, and at
    /// most every ten seconds; leaving the screen or the app saves at once
    /// (docs/08 §7).
    public func noteRow(_ statusID: String, isVisible: Bool) {
        guard tracksReadingPosition else { return }
        if isVisible {
            visibleStatusIDs.insert(statusID)
        } else {
            visibleStatusIDs.remove(statusID)
        }
        let delay = max(2, 10 - Date().timeIntervalSince(lastMarkerSave))
        markerSaveTask?.cancel()
        markerSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.saveReadingMarker()
        }
    }

    /// The newest post on screen. In a newest-first list that is the topmost
    /// one, and it is what Mastodon's home marker means: the last post read.
    var topmostVisibleStatusID: String? {
        guard !visibleStatusIDs.isEmpty else { return nil }
        return index.statusIDs.first(where: visibleStatusIDs.contains)
    }

    /// Saves the topmost visible post as the home marker, locally and on the
    /// server — only ever forwards.
    ///
    /// This used to save the row *below* the divider, once per session. In a
    /// newest-first list that row is older than the marker, so the store
    /// refused it while the copy in memory moved back, and the next launch
    /// restored to a post the reader had long scrolled past.
    ///
    /// Async because the local marker lives in an actor — the store — and a
    /// marker that is only saved off the main actor is the one thing this
    /// must not do.
    public func saveReadingMarker() async {
        guard tracksReadingPosition, let top = topmostVisibleStatusID,
            Self.movesMarkerForward(to: top, from: savedMarkerID)
        else { return }
        savedMarkerID = top
        markerMovedThisVisit = true
        lastMarkerSave = Date()
        do {
            _ = try await session.supportStore.advanceMarker(
                accountID: session.id, timeline: "home", to: top)
        } catch {
            logger.debug(
                "could not advance local home marker: \(String(describing: error), privacy: .public)"
            )
        }
        // The server keeps the marker other devices read; a failure here is
        // retried by the next save, which carries the newer post anyway.
        do {
            _ = try await session.client.send(Endpoint.markers.write(home: top, notifications: nil))
        } catch {
            logger.debug(
                "could not sync home marker: \(String(describing: error), privacy: .public)")
        }
    }

    nonisolated static func movesMarkerForward(to candidate: String, from saved: String?) -> Bool {
        guard let saved, !saved.isEmpty else { return true }
        return SupportStore.isNewer(candidate, than: saved)
    }

    /// The rows with the "caught up" divider above the visit's marker, and
    /// nowhere else. None when the marker is the newest post — there is
    /// nothing new above it to divide from — or not loaded.
    nonisolated static func placingDivider(
        in rows: [TimelineRow], above markerID: String?
    ) -> [TimelineRow] {
        var placed = rows.filter {
            if case .caughtUpDivider = $0 { return false }
            return true
        }
        guard let markerID,
            let index = placed.firstIndex(where: { $0.status?.id == markerID }),
            placed[..<index].contains(where: { $0.status != nil })
        else { return placed }
        placed.insert(.caughtUpDivider(above: markerID), at: index)
        return placed
    }

    /// The one way rows change wholesale: the divider placed, then a single
    /// assignment, so the index and the list are rebuilt once.
    private func commit(_ newRows: [TimelineRow]) {
        rows = Self.placingDivider(in: newRows, above: visitMarkerID)
    }

    /// Store updates arrive on whichever thread posted them; the model only
    /// hears them on the main actor. The subscription ends when the returned
    /// object goes.
    nonisolated static func observeStatusUpdates(
        _ receive: @escaping @MainActor @Sendable (TimelineStatusUpdate) -> Void
    ) -> NotificationSubscription {
        NotificationSubscription(name: TimelineStatusUpdate.notification) { notification in
            guard let update = notification.object as? TimelineStatusUpdate else { return }
            Task { @MainActor in receive(update) }
        }
    }

    nonisolated static func replacing(_ updated: Status, in rows: [TimelineRow]) -> [TimelineRow] {
        rows.map { row in
            guard var status = row.status else { return row }
            if status.id == updated.id { return .status(updated) }
            if status.reblog?.value.id == updated.id {
                status.reblog = Box(updated)
                return .status(status)
            }
            return row
        }
    }

    /// Every status in `updates`, keyed by id, replaced in one pass — as a
    /// post, or inside a boost of it.
    nonisolated static func replacing(
        _ updates: [String: Status], in rows: [TimelineRow]
    ) -> [TimelineRow] {
        guard !updates.isEmpty else { return rows }
        return rows.map { row in
            guard var status = row.status else { return row }
            if let updated = updates[status.id] { return .status(updated) }
            if let inner = status.reblog?.value.id, let updated = updates[inner] {
                status.reblog = Box(updated)
                return .status(status)
            }
            return row
        }
    }

    /// The rows less every post the removal names: by id, a boost of one of
    /// them, and for a block or mute everything the person wrote or boosted.
    /// Gaps and the caught-up divider stay where they are — they mark places
    /// in the list, not posts.
    nonisolated static func removing(
        _ removal: TimelineStatusRemoval, from rows: [TimelineRow]
    ) -> [TimelineRow] {
        rows.filter { row in
            guard let status = row.status else { return true }
            return !removal.removes(status)
        }
    }

    /// Interaction confirmations only have to outlive a page that was still
    /// in flight when the confirmation landed, so they are time-boxed and
    /// pruned on every store.
    nonisolated static func pruneConfirmations(_ stamps: inout [String: Date], now: Date) {
        stamps = stamps.filter { now.timeIntervalSince($0.value) < 60 }
    }

    private var storageKey: String { key.storageKey }

    // MARK: - Loading

    /// Paints from cache instantly; refreshes only if the cache is stale.
    public func appear() async {
        if rows.isEmpty { await loadFromCache() }
        await refreshIfStale(olderThan: 60)
    }

    /// A refresh unless one landed within `interval` — on appearing, and on
    /// coming back to the foreground.
    public func refreshIfStale(olderThan interval: TimeInterval) async {
        let isStale = lastRefresh.map { Date().timeIntervalSince($0) > interval } ?? true
        if isStale { await refresh() }
    }

    public func loadFromCache() async {
        do {
            let cached = try await session.timelineStore.cachedTimeline(
                accountID: session.id, timelineKey: storageKey)
            await verdicts.load(from: session)
            await verdicts.warm(cached.compactMap(\.status))
            commit(applyFilters(to: cached))
            let statuses = cached.compactMap(\.status)
            Task { await indexLinks(statuses) }
        } catch {
            logger.error("cache read failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// How a refresh merges what it fetched.
    ///
    /// Every refresh fetches the **head** of the timeline — `since_id`
    /// responses never carry existing posts whose counts, flags or text have
    /// changed, and statuses are cached per id and shared between timelines,
    /// so the head is how an edited post or another source's copy of a
    /// shared one is put right.
    ///
    /// The merge is what differs. With rows to keep it is `.newer`, even on a
    /// model's first fetch: the head goes on top of the cache and a gap opens
    /// only where the two do not meet. The first fetch used to merge cold,
    /// which kept the forty posts it fetched and dropped up to five hundred
    /// cached ones — the post the reader was on among them.
    ///
    /// Cold is for a list with nothing to keep, for a gap that can only be
    /// filled by starting again (`fillGap`), and for the first fetch of a list
    /// that pages only by link: there the cursor to the next page comes from
    /// the server, and a merged cache would leave no cursor that reaches below
    /// it.
    ///
    /// `nonisolated` and static because it reads no state: what it decides
    /// from is handed to it, so a test can pin it without a session.
    nonisolated static func refreshDirection(
        hasRows: Bool, hasFetchedBefore: Bool, pagesOnlyByLink: Bool, replacesCache: Bool
    ) -> TimelineMerge.Direction {
        guard hasRows, !replacesCache else { return .cold }
        if pagesOnlyByLink && !hasFetchedBefore { return .cold }
        return .newer
    }

    /// One refresh in flight per timeline; a second coalesces onto the first.
    ///
    /// - Parameter revealingArrivals: a pull to refresh. The pull happens at
    ///   the top, and the reader asked for what is new, so new posts go
    ///   straight into the list rather than behind the pill.
    public func refresh(revealingArrivals: Bool = false) async {
        if let refreshTask {
            await refreshTask.value
            if revealingArrivals { revealPendingRows() }
            return
        }
        let task = Task { await performRefresh(revealingArrivals: revealingArrivals) }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh(revealingArrivals: Bool) async {
        isRefreshing = true
        defer { isRefreshing = false }

        let direction = Self.refreshDirection(
            hasRows: rows.contains { $0.status != nil },
            hasFetchedBefore: lastRefresh != nil,
            pagesOnlyByLink: key.source.pagesOnlyByLink,
            replacesCache: replacesCacheOnNextRefresh)
        replacesCacheOnNextRefresh = false
        if direction == .cold { hasMoreOlderPosts = true }

        do {
            // When the page was asked for: an interaction confirmed after this
            // instant may not be in it, however late the page arrives.
            let requestedAt = Date()
            let harvest = try await fetch(anchor: .cold)
            errorMessage = nil
            isOffline = false
            lastRefresh = Date()

            guard !harvest.statuses.isEmpty || direction == .cold else { return }

            // A like the reader can see must survive a page that was already
            // on the wire: confirmed after the page was asked for, or still on
            // its way to the server. Their copies stay, in the store and here.
            let protected = protectedStatusIDs(
                in: harvest.statuses.map(\.displayed.id), since: requestedAt)
            let merged = try await session.timelineStore.apply(
                page: harvest.statuses, accountID: session.id, timelineKey: storageKey,
                direction: direction, pageWasFull: harvest.pageWasFull, preserving: protected)

            await verdicts.warm(harvest.statuses)
            // Asked again after the awaits: an interaction may have landed
            // while the merge was being written.
            let local = localCopies(
                of: protectedStatusIDs(
                    in: harvest.statuses.map(\.displayed.id), since: requestedAt))
            let incoming = Self.replacing(local, in: applyFilters(to: merged))

            if direction == .cold || !rows.contains(where: { $0.status != nil }) {
                pendingRows = []
                pendingNewCount = 0
                commit(incoming)
                nextCursor = harvest.nextCursor
                hasMoreOlderPosts = harvest.pageWasFull || harvest.nextCursor != nil
            } else {
                let knownIDs = Set(rows.map(\.id))
                let arrivals = incoming.filter { $0.status != nil && !knownIDs.contains($0.id) }
                let showsDirectly =
                    arrivals.isEmpty || revealingArrivals || readerIsAtTop
                    || !session.settings.showNewPostsPill
                if showsDirectly {
                    pendingRows = []
                    pendingNewCount = 0
                    commit(incoming)
                } else {
                    // Hold new rows behind a pill rather than moving what the
                    // person is reading — but not the updated counts and flags
                    // of the rows already on screen alongside them.
                    var fresh: [String: Status] = [:]
                    for status in harvest.statuses.map(\.displayed)
                    where !protected.contains(status.id) {
                        fresh[status.id] = status
                    }
                    commit(Self.replacing(local, in: Self.replacing(fresh, in: rows)))
                    pendingRows = incoming
                    pendingNewCount = arrivals.count
                }
            }

            // Painting the rows is the user-visible critical path. Parsing
            // rich text and promoting optional capabilities can finish just
            // behind it without holding the whole first screen hostage.
            let statuses = harvest.statuses
            Task { await indexLinks(statuses) }
            await session.latchCapabilities(observing: harvest.statuses)
        } catch {
            await handle(error)
        }
    }

    /// Statuses among `ids` whose copy on screen is newer than a page asked
    /// for at `requestedAt`.
    private func protectedStatusIDs(in ids: [String], since requestedAt: Date) -> Set<String> {
        let now = Date()
        Self.pruneConfirmations(&confirmations, now: now)
        Self.pruneConfirmations(&inFlight, now: now)
        return Set(
            ids.filter { id in
                inFlight[id] != nil || (confirmations[id].map { $0 > requestedAt } ?? false)
            })
    }

    /// The copies on screen, or held behind the pill, of the given statuses.
    private func localCopies(of ids: Set<String>) -> [String: Status] {
        guard !ids.isEmpty else { return [:] }
        var copies: [String: Status] = [:]
        for row in pendingRows + rows {
            guard let shown = row.status?.displayed, ids.contains(shown.id) else { continue }
            copies[shown.id] = shown
        }
        return copies
    }

    /// A post this account just made. Shown at once on the feeds where it
    /// belongs: Home, the account's own media modes, and any pending rows come
    /// along so nothing is lost.
    public func insertOwn(_ status: Status) async {
        guard key.source == .home else { return }
        guard rows.contains(where: { $0.id == status.id }) == false else { return }
        switch key.mode {
        case .home: break
        case .photos:
            guard status.mediaAttachments.contains(where: { $0.type == .image }) else { return }
        case .video, .shorts:
            // The server-side only_video filter is best-effort on older
            // Social versions, so enforce the contract locally as well.
            guard status.mediaAttachments.contains(where: { $0.isVideo }) else { return }
        case .news, .audio: return
        }
        _ = try? await session.timelineStore.apply(
            page: [status], accountID: session.id, timelineKey: storageKey,
            direction: .newer, pageWasFull: false)
        commit([.status(status)] + rows)
        if !pendingRows.isEmpty { pendingRows.insert(.status(status), at: 0) }
    }

    public func revealPendingRows() {
        guard !pendingRows.isEmpty else { return }
        commit(pendingRows)
        pendingRows = []
        pendingNewCount = 0
    }

    /// Rows from a merge that also holds the posts waiting behind the pill —
    /// paging older, filling a gap. The pill keeps them: shown here, they
    /// would land above the reader and push the list down under them.
    private func commitMerged(_ incoming: [TimelineRow]) {
        guard pendingNewCount > 0 else {
            commit(incoming)
            return
        }
        let shown = Set(rows.map(\.id))
        let held = Set(pendingRows.map(\.id)).subtracting(shown)
        commit(incoming.filter { !held.contains($0.id) })
        pendingRows = incoming
    }

    private var hasMoreOlderPosts = true

    /// Request the next page while a screenful of cached posts remains.
    public func prefetchOlder(near statusID: String) async {
        let ids = rows.compactMap(\.status).map(\.id)
        guard Self.shouldPrefetchOlder(visibleID: statusID, loadedIDs: ids) else { return }
        await loadOlder()
    }

    static func shouldPrefetchOlder(visibleID: String, loadedIDs: [String]) -> Bool {
        guard let index = loadedIDs.firstIndex(of: visibleID) else { return false }
        return loadedIDs.count - index - 1 < 8
    }

    public func loadOlder() async {
        guard hasMoreOlderPosts, !isPagingOlder,
            let oldest = rows.compactMap(\.status).last?.id
        else { return }
        isPagingOlder = true
        defer { isPagingOlder = false }

        let anchor: PageAnchor
        if let nextCursor {
            anchor = .url(nextCursor)
        } else if key.source.pagesOnlyByLink {
            // Favourites and bookmarks page by the mark's id; without the
            // server's cursor there is no older page this side can name.
            hasMoreOlderPosts = false
            return
        } else {
            anchor = .olderThan(oldest)
        }

        do {
            let harvest = try await fetch(anchor: anchor)
            isOffline = false
            errorMessage = nil
            guard !harvest.statuses.isEmpty else {
                // A client-side media filter can leave a fetched page empty
                // even though the server still has another cursor.
                nextCursor = harvest.nextCursor
                hasMoreOlderPosts = harvest.nextCursor != nil
                return
            }
            let merged = try await session.timelineStore.apply(
                page: harvest.statuses, accountID: session.id, timelineKey: storageKey,
                direction: .older, pageWasFull: harvest.pageWasFull)
            await verdicts.warm(harvest.statuses)
            commitMerged(applyFilters(to: merged))
            nextCursor = harvest.nextCursor
            hasMoreOlderPosts = harvest.pageWasFull || harvest.nextCursor != nil
            let statuses = harvest.statuses
            Task { await indexLinks(statuses) }
            await session.latchCapabilities(observing: harvest.statuses)
        } catch {
            await handle(error)
        }
    }

    /// Fills a hole rather than closing it blindly.
    public func fillGap(id gapID: String) async {
        guard let index = rows.firstIndex(where: { $0.id == gapID }) else { return }
        if key.source.pagesOnlyByLink {
            // No status id can name the window under the gap (see
            // `pagesOnlyByLink`), so the list is loaded again from the top.
            replacesCacheOnNextRefresh = true
            await refresh()
            return
        }
        let above = rows[..<index].compactMap(\.status).last?.id

        do {
            let harvest = try await fetch(anchor: above.map { .olderThan($0) } ?? .cold)
            let merged = try await session.timelineStore.apply(
                page: harvest.statuses, accountID: session.id, timelineKey: storageKey,
                direction: .fillingGap(id: gapID), pageWasFull: harvest.pageWasFull)
            await verdicts.warm(harvest.statuses)
            commitMerged(applyFilters(to: merged))
        } catch {
            await handle(error)
        }
    }

    // MARK: - Fetching

    private struct Harvest {
        var statuses: [Status]
        var pageWasFull: Bool
        var nextCursor: URL?
    }

    /// Where the server cannot narrow, the client filters and over-fetches —
    /// bounded at five upstream pages per user-visible page, stopping early on
    /// a short page so no rows are skipped (docs/06 §2).
    private func fetch(anchor: PageAnchor) async throws -> Harvest {
        let serverFilters = TimelineFilters.forMode(key.mode, capabilities: session.capabilities)
        let limit = Endpoint.defaultLimit
        let needsClientFiltering = key.mode != .home && serverFilters.isEmpty
        let budget =
            needsClientFiltering
            ? min(
                OverFetch.maximumUpstreamPages,
                OverFetch.multiplier(for: key.mode, serverFilters: serverFilters))
            : 1

        var collected: [Status] = []
        var cursor: URL? = { if case .url(let url) = anchor { return url } else { return nil } }()
        var lastPageWasFull = false
        var pagesFetched = 0

        while pagesFetched < budget {
            let page: Paginated<LossyArray<Status>>
            if let cursor {
                page = try await session.client.page(
                    LossyArray<Status>.self, following: cursor, limit: limit)
            } else {
                let endpoint = Endpoint.timelines.timeline(
                    key.source, filters: serverFilters, limit: limit, anchor: anchor)
                page = try await session.client.page(
                    LossyArray<Status>.self, from: endpoint, limit: limit)
            }

            pagesFetched += 1
            lastPageWasFull = page.rawCount >= limit
            cursor = page.link.next
            collected.append(contentsOf: page.value.elements)

            // A short page is the last one; there is nothing more to over-fetch.
            if !lastPageWasFull || cursor == nil { break }
            if needsClientFiltering && matching(collected).count >= limit { break }
        }

        let kept = needsClientFiltering ? matching(collected) : collected
        return Harvest(statuses: kept, pageWasFull: lastPageWasFull, nextCursor: cursor)
    }

    private func matching(_ statuses: [Status]) -> [Status] {
        guard key.mode != .home else { return statuses }
        return statuses.filter { ContentClassifier.classify($0).belongs(in: key.mode) }
    }

    /// Parses a page's content before its rows are handed to the list.
    ///
    /// `RichTextView` falls back to plain text for one frame when a parse is
    /// not yet cached; warming the whole page here means that path is only ever
    /// taken for content that arrived some other way.
    ///
    /// The same pass records each post's web links for the links rotor, so
    /// that index costs no second parse.
    private func indexLinks(_ statuses: [Status]) async {
        var found: [String: [URL]] = [:]
        for status in statuses {
            let links = await RichTextCache.shared.richText(for: status).webLinks
            if !links.isEmpty { found[status.id] = links }
        }
        guard !found.isEmpty else { return }
        webLinks.merge(found) { _, new in new }
    }

    // MARK: - Prefetching

    /// Ten rows ahead, and cancel what is now behind. Bounded rather than
    /// greedy: the point is that the next screenful is ready, not that the
    /// whole timeline is downloaded (docs/05 §3).
    private static let prefetchDistance = 10
    private var lastPrefetchIndex = 0

    public func prefetchMedia(around rowID: String) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }

        let ahead = rows[index..<min(index + Self.prefetchDistance, rows.count)]
        let behind =
            index > Self.prefetchDistance
            ? Array(rows[0..<(index - Self.prefetchDistance)]) : []

        let isScrollingDown = index >= lastPrefetchIndex
        lastPrefetchIndex = index

        let geometry = prefetchGeometry
        let wanted = Self.groupedBySize(ahead.flatMap { Self.prefetchRequests($0, geometry) })
        let unwanted =
            isScrollingDown && !behind.isEmpty
            ? Self.groupedBySize(behind.flatMap { Self.prefetchRequests($0, geometry) }) : []

        Task {
            for (size, urls) in wanted {
                await ImageLoader.shared.prefetch(urls, targetSize: size, scale: geometry.scale)
            }
            // Only cancel on a direction change; cancelling on every row would
            // undo the work the previous row just started.
            for (size, urls) in unwanted {
                await ImageLoader.shared.cancelPrefetch(
                    urls, targetSize: size, scale: geometry.scale)
            }
        }
    }

    /// The images a row will ask for, at the sizes it will ask for them.
    ///
    /// A prefetch at one fixed 400×400 landed in a different cache entry from
    /// every request a row actually made, so it downloaded the bytes and then
    /// decoded twice. These follow `MediaGrid`'s layout: one item spans the
    /// content width (up to its 300 pt cap), two share a 16:9 strip, more make
    /// a grid of squares; avatars are the row's own avatar size.
    nonisolated static func prefetchRequests(
        _ row: TimelineRow, _ geometry: PrefetchGeometry
    ) -> [(url: URL, size: CGSize)] {
        guard let status = row.status else { return [] }
        let target = status.displayed
        let width = max(geometry.contentWidth, 1)
        var requests: [(url: URL, size: CGSize)] = []

        let media = target.mediaAttachments.compactMap(\.displayImageURL)
        let mediaSize: CGSize =
            switch media.count {
            case 0: .zero
            case 1: CGSize(width: width, height: min(width, MediaGrid.maximumRowHeight))
            case 2: CGSize(width: width / 2, height: width * 9 / 16)
            default: CGSize(width: width / 2, height: width / 2)
            }
        requests += media.prefix(4).map { ($0, mediaSize) }

        if let avatar = target.account.preferredAvatarURL {
            // A boost's row draws its avatar smaller (`StatusRow.Emphasis`).
            let side = geometry.avatarSize * (status.booster != nil ? 0.82 : 1)
            requests.append((avatar, CGSize(width: side, height: side)))
        }
        if media.isEmpty, let card = target.card?.image {
            requests.append((card, CGSize(width: width, height: width / 1.91)))
        }
        return requests
    }

    /// One prefetch call per size, in first-seen order.
    nonisolated static func groupedBySize(
        _ requests: [(url: URL, size: CGSize)]
    ) -> [(size: CGSize, urls: [URL])] {
        var groups: [(size: CGSize, urls: [URL])] = []
        for request in requests {
            if let index = groups.firstIndex(where: { $0.size == request.size }) {
                groups[index].urls.append(request.url)
            } else {
                groups.append((request.size, [request.url]))
            }
        }
        return groups
    }

    // MARK: - Filters

    /// Applied when rows are set, and the verdicts cached; the cache is
    /// dropped when the next filter expiry passes, so a filter that expires
    /// stops hiding without a refetch (docs/04 §6).
    private func applyFilters(to rows: [TimelineRow]) -> [TimelineRow] {
        let settings = session.settings
        return rows.filter { row in
            guard let status = row.status else { return true }
            if !settings.showBoosts && status.isBoost { return false }
            if !settings.showReplies && status.displayed.inReplyToID != nil { return false }
            return decision(for: status) != .hide
        }
    }

    private func decision(for status: Status) -> FilterEvaluator.Decision {
        verdicts.decision(for: status)
    }

    public func filterWarning(for status: Status) -> String? {
        verdicts.warning(for: status)
    }

    // MARK: - Errors

    private func handle(_ error: any Error) async {
        await session.handle(error)

        if case APIError.transport = error {
            isOffline = true
            // Cached content stays; the strip is inline, never a blocking overlay.
            errorMessage = nil
            return
        }
        if case APIError.cancelled = error { return }

        isOffline = false
        errorMessage =
            (error as? APIError)?.errorDescription
            ?? String(localized: "Something went wrong.", comment: "Generic timeline error")
    }
}

/// Client-side evaluation of v2 filters.
public enum FilterEvaluator {
    public enum Decision: Sendable, Hashable {
        case show
        case warn(title: String)
        case hide
    }

    /// The verdict for one status: the server's own (`status.filtered`)
    /// together with the filters applied locally, hiding winning over
    /// warning wherever either says so.
    ///
    /// `text` is the post's plain text and content warning, when the caller
    /// has parsed it already; otherwise the content is parsed here. Keywords
    /// are matched against what the reader sees, never against the HTML —
    /// matching markup made "span" or "href" filter every post with a link,
    /// and `&amp;` stopped "Tom & Jerry" from matching at all.
    public static func decision(
        for status: Status, filters: [Filter], context: FilterContext, now: Date = Date(),
        text: String? = nil
    ) -> Decision {
        let target = status.displayed
        var warning: String?

        switch serverDecision(for: status, context: context, now: now) {
        case .hide: return .hide
        case .warn(let title): warning = title
        case .show: break
        }

        let active = filters.filter { !$0.isExpired(at: now) && $0.context.contains(context) }
        guard !active.isEmpty else { return warning.map { .warn(title: $0) } ?? .show }

        let needsText = active.contains { !$0.keywords.isEmpty }
        let haystack = needsText ? (text ?? searchableText(target)).lowercased() : ""
        let words =
            needsText
            ? Set(
                haystack.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            : []

        for filter in active {
            let statusMatch = filter.statuses.contains { $0.statusID == target.id }
            let keywordMatch = filter.keywords.contains { keyword in
                let needle = keyword.keyword.lowercased()
                guard !needle.isEmpty else { return false }
                guard keyword.wholeWord else { return haystack.contains(needle) }
                // A whole-word phrase ("tom & jerry") is still a phrase; only
                // a single word can be looked up among the words.
                if needle.contains(where: { !$0.isLetter && !$0.isNumber }) {
                    return haystack.contains(needle)
                }
                return words.contains(needle)
            }

            guard statusMatch || keywordMatch else { continue }
            switch filter.filterAction {
            case .hide: return .hide
            case .warn, .blur, .unknownCase: warning = warning ?? filter.title
            }
        }
        return warning.map { .warn(title: $0) } ?? .show
    }

    /// What the server already decided: Mastodon 4 and Nextcloud Social send
    /// the matching filters with each status, on the status and on what it
    /// boosts. A filter the app has not synced yet still applies.
    static func serverDecision(
        for status: Status, context: FilterContext, now: Date
    ) -> Decision {
        let results = (status.filtered ?? []) + (status.reblog?.value.filtered ?? [])
        var warning: String?
        for result in results {
            let filter = result.filter
            guard !filter.isExpired(at: now) else { continue }
            guard filter.context.isEmpty || filter.context.contains(context) else { continue }
            switch filter.filterAction {
            case .hide: return .hide
            case .warn, .blur, .unknownCase: warning = warning ?? filter.title
            }
        }
        return warning.map { .warn(title: $0) } ?? .show
    }

    /// The words a keyword filter searches: the post as read, and its
    /// content warning.
    static func searchableText(_ status: Status) -> String {
        StatusHTMLParser().plainText(status.content) + " " + status.spoilerText
    }

    /// When the next filter stops applying, so cached verdicts can be
    /// dropped exactly then.
    static func nextExpiry(of filters: [Filter], after now: Date) -> Date? {
        filters.compactMap(\.expiresAt).filter { $0 > now }.min()
    }
}

/// One status's content, as far as filtering is concerned: a post that is
/// edited gets a new verdict.
struct FilterCacheKey: Hashable {
    let statusID: String
    let content: Int
    let spoiler: Int

    init(_ status: Status) {
        let target = status.displayed
        statusID = status.id
        content = target.content.hashValue
        spoiler = target.spoilerText.hashValue
    }
}

/// The layout the timeline's rows are drawn in, as the view measured it.
public struct PrefetchGeometry: Sendable, Equatable {
    /// The width a row's content column gets: the row less its insets, the
    /// avatar and the gap after it.
    public var contentWidth: Double
    public var avatarSize: Double
    public var scale: Double

    public init(contentWidth: Double = 300, avatarSize: Double = 46, scale: Double = 2) {
        self.contentWidth = contentWidth
        self.avatarSize = avatarSize
        self.scale = scale
    }
}

/// `rows` as the view reads it, derived once per change.
struct TimelineIndex {
    let statusIDs: [String]
    let statuses: [Status]
    private let byID: [String: Status]
    let linkEntries: [LinkRotorEntry]

    init(rows: [TimelineRow], webLinks: [String: [URL]]) {
        let statuses = rows.compactMap(\.status)
        self.statuses = statuses
        statusIDs = statuses.map(\.id)
        byID = Dictionary(statuses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        linkEntries = statuses.flatMap { status in
            (webLinks[status.id] ?? []).enumerated().map { index, url in
                LinkRotorEntry(
                    id: "\(status.id)-\(index)", statusID: status.id,
                    label: LinkRotorEntry.label(for: url))
            }
        }
    }

    func status(id: String) -> Status? { byID[id] }
}
