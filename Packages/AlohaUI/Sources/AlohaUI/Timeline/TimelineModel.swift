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
    private var filters: [Filter] = [] {
        didSet {
            guard filters != oldValue else { return }
            filterDecisions = [:]
            nextFilterExpiry = FilterEvaluator.nextExpiry(of: filters, after: Date())
        }
    }
    private var nextCursor: URL?
    private var refreshTask: Task<Void, Never>?
    private var lastRefresh: Date?
    @ObservationIgnored private var statusUpdates: NotificationSubscription?
    /// When the server last confirmed an interaction with a status, per id.
    /// A page fetched *before* that moment carries the older copy and must
    /// not overwrite the confirmation again (see `performRefresh`).
    @ObservationIgnored private var confirmations: [String: Date] = [:]
    /// The post ID that marks "you're caught up" on the home timeline.
    /// Loaded from the local marker store; when the reader scrolls past the
    /// divider below this post, the marker advances. Read by the view to
    /// restore where the reader got to (docs/08 §7).
    @ObservationIgnored private(set) public var caughtUpMarkerID: String?
    /// Whether the marker has been advanced this session (to avoid
    /// re-syncing on every appearance of the same row).
    @ObservationIgnored private var markerAdvancedThisSession = false
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
    /// every evaluation of the row. Cleared when the filters change, and when
    /// the next filter expiry passes.
    @ObservationIgnored private var filterDecisions: [FilterCacheKey: FilterEvaluator.Decision] =
        [:]
    /// Plain text for keyword matching, parsed off the main actor before a
    /// page is filtered. Only collected while a keyword filter exists.
    @ObservationIgnored private var filterTexts: [FilterCacheKey: String] = [:]
    @ObservationIgnored private var nextFilterExpiry: Date?

    private let logger = Logger(subsystem: "social.aloha.app", category: "timeline")

    public init(key: TimelineKey, session: AccountSession) {
        self.key = key
        self.session = session
        statusUpdates = Self.observeStatusUpdates { [weak self] update in
            guard let self, update.accountID == self.session.id else { return }
            let now = Date()
            Self.pruneConfirmations(&self.confirmations, now: now)
            self.confirmations[update.status.id] = now
            self.rows = Self.replacing(update.status, in: self.rows)
            self.pendingRows = Self.replacing(update.status, in: self.pendingRows)
        }

        // Load the "caught up" marker for the home timeline.
        if key.mode == .home, key.source == .home {
            Task { await loadCaughtUpMarker() }
        }
    }

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
        if let local, !local.isEmpty { applyCaughtUpMarker(local) }

        let server = try? await session.client.decode(
            MarkerSet.self, from: Endpoint.markers.read
        ).home?.lastReadID
        guard let newest = Self.newestMarker(local: local, server: server), newest != local
        else { return }
        _ = try? await session.supportStore.advanceMarker(
            accountID: session.id, timeline: "home", to: newest)
        applyCaughtUpMarker(newest)
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

    /// Moves the divider to a new marker rather than adding a second one.
    private func applyCaughtUpMarker(_ id: String) {
        caughtUpMarkerID = id
        rows.removeAll { row in
            if case .caughtUpDivider = row { return true }
            return false
        }
        ensureCaughtUpDivider()
    }

    /// Advances the caught-up marker to the given post ID, both locally
    /// and on the server (fire-and-forget).
    /// Called from the view when the reader passes the divider.
    ///
    /// Async because the local marker lives in an actor — the store — and a
    /// marker that is only saved off the main actor is the one thing this
    /// must not do.
    func advanceCaughtUpMarker(to statusID: String) async {
        guard !markerAdvancedThisSession else { return }
        markerAdvancedThisSession = true
        caughtUpMarkerID = statusID
        // Local store.
        do {
            _ = try await session.supportStore.advanceMarker(
                accountID: session.id, timeline: "home", to: statusID)
        } catch {
            logger.debug(
                "could not advance local home marker: \(String(describing: error), privacy: .public)"
            )
        }
        // Server sync, fire-and-forget.
        let endpoint = Endpoint.markers.write(home: statusID, notifications: nil)
        do {
            _ = try await session.client.send(endpoint)
        } catch {
            logger.debug(
                "could not sync home marker: \(String(describing: error), privacy: .public)")
        }
    }

    /// Ensures the "caught up" divider is present in `rows` when the marker
    /// ID is known and present in the timeline. Idempotent.
    private func ensureCaughtUpDivider() {
        guard let markerID = caughtUpMarkerID,
            let idx = rows.firstIndex(where: { $0.status?.id == markerID })
        else { return }
        // Already present?
        if rows.indices.contains(idx + 1),
            case .caughtUpDivider = rows[idx + 1]
        {
            return
        }
        rows.insert(.caughtUpDivider(after: markerID), at: idx + 1)
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
        let isStale = lastRefresh.map { Date().timeIntervalSince($0) > 60 } ?? true
        if isStale { await refresh() }
    }

    public func loadFromCache() async {
        do {
            let cached = try await session.timelineStore.cachedTimeline(
                accountID: session.id, timelineKey: storageKey)
            filters = (try? await session.supportStore.activeFilters(accountID: session.id)) ?? []
            await warmFilterTexts(cached.compactMap(\.status))
            rows = applyFilters(to: cached)
            ensureCaughtUpDivider()
            let statuses = cached.compactMap(\.status)
            Task { await indexLinks(statuses) }
        } catch {
            logger.error("cache read failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// What a refresh should ask the server for, and how the answer merges.
    ///
    /// A model that has never fetched asks for the **head** of the timeline,
    /// even when the cache handed it rows to draw immediately.
    ///
    /// Deciding this from the rows alone conflated "I have a cache" with "I
    /// have fetched": a freshly built model with a warm cache asked only for
    /// what was newer, the server had nothing newer, and the cache was left on
    /// screen however old or wrong it was. Switching the source rebuilds the
    /// model by design (`AppShell.timelineChrome` keys it on the source), so
    /// the other source's copy of a shared post stayed up — the title and the
    /// toggle said My feed while the rows still read Local.
    ///
    /// Statuses are cached per id and shared between timelines, so this is not
    /// only about the toggle: it is how an edited post, or one whose counts
    /// have moved, is stale until something forces a cold load.
    ///
    /// Pulled out of `performRefresh` and made static so it can be tested. It
    /// is four lines of branching that cost a visible bug once, and nothing
    /// about it needs a session, a store or a server to check.
    ///
    /// `nonisolated` because it reads no state: the two things it decides from
    /// are handed to it. That is also what lets a test call it without hopping
    /// to the main actor.
    nonisolated static func refreshPlan(
        hasFetchedBefore: Bool, newestRowID: String?
    ) -> (anchor: PageAnchor, direction: TimelineMerge.Direction) {
        guard hasFetchedBefore, let newestRowID else { return (.cold, .cold) }
        return (.newerThan(newestRowID), .newer)
    }

    /// One refresh in flight per timeline; a second coalesces onto the first.
    public func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let plan = Self.refreshPlan(
            hasFetchedBefore: lastRefresh != nil,
            newestRowID: rows.compactMap(\.status).first?.id)
        let direction = plan.direction
        if direction == .cold { hasMoreOlderPosts = true }

        do {
            // Fetch the head as well as new arrivals: since_id responses never
            // include existing posts whose counts or interaction flags changed.
            let harvest = try await fetch(anchor: .cold)
            // When this response arrived, not when the server produced it: a
            // confirmation stamped after this instant is newer than anything
            // the page can say about its status.
            let harvestReceivedAt = Date()
            errorMessage = nil
            isOffline = false
            lastRefresh = Date()

            guard !harvest.statuses.isEmpty || direction == .cold else { return }

            let merged = try await session.timelineStore.apply(
                page: harvest.statuses, accountID: session.id, timelineKey: storageKey,
                direction: direction, pageWasFull: harvest.pageWasFull)

            await warmFilterTexts(harvest.statuses)
            let filtered = applyFilters(to: merged)

            // A new-post pill must not hold updated counts on existing rows
            // hostage alongside the arrivals it is deliberately withholding.
            Self.pruneConfirmations(&confirmations, now: harvestReceivedAt)
            for status in harvest.statuses {
                // ...unless the server confirmed an interaction with that
                // status while this page was on the wire. That confirmation is
                // newer than the page's copy; applying the copy again would
                // visibly revert the like or boost until the next refresh.
                if let confirmedAt = confirmations[status.id], confirmedAt > harvestReceivedAt {
                    continue
                }
                rows = Self.replacing(status.displayed, in: rows)
                ensureCaughtUpDivider()
            }

            if direction == .cold || rows.isEmpty {
                rows = filtered
                nextCursor = harvest.nextCursor
                hasMoreOlderPosts = harvest.pageWasFull || harvest.nextCursor != nil
                ensureCaughtUpDivider()
            } else {
                // Hold new rows behind a pill rather than moving what the person
                // is reading.
                let knownIDs = Set(rows.map(\.id))
                let arrivals = filtered.filter { !knownIDs.contains($0.id) }
                if arrivals.isEmpty {
                    rows = filtered
                } else if session.settings.showNewPostsPill {
                    pendingRows = filtered
                    pendingNewCount = arrivals.compactMap(\.status).count
                } else {
                    rows = filtered
                    ensureCaughtUpDivider()
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
        rows.insert(.status(status), at: 0)
        if !pendingRows.isEmpty { pendingRows.insert(.status(status), at: 0) }
    }

    public func revealPendingRows() {
        guard !pendingRows.isEmpty else { return }
        rows = pendingRows
        ensureCaughtUpDivider()
        pendingRows = []
        pendingNewCount = 0
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
            await warmFilterTexts(harvest.statuses)
            rows = applyFilters(to: merged)
            ensureCaughtUpDivider()
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
            lastRefresh = nil
            await refresh()
            return
        }
        let above = rows[..<index].compactMap(\.status).last?.id

        do {
            let harvest = try await fetch(anchor: above.map { .olderThan($0) } ?? .cold)
            let merged = try await session.timelineStore.apply(
                page: harvest.statuses, accountID: session.id, timelineKey: storageKey,
                direction: .fillingGap(id: gapID), pageWasFull: harvest.pageWasFull)
            await warmFilterTexts(harvest.statuses)
            rows = applyFilters(to: merged)
            ensureCaughtUpDivider()
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

    private var hasKeywordFilters: Bool {
        filters.contains { !$0.keywords.isEmpty }
    }

    /// Parses the text keyword filters search, off the main actor, so the
    /// verdicts that follow never parse HTML on it. Nothing to do — and
    /// nothing parsed — while no filter has a keyword.
    private func warmFilterTexts(_ statuses: [Status]) async {
        guard hasKeywordFilters else { return }
        for status in statuses {
            let key = FilterCacheKey(status)
            guard filterTexts[key] == nil else { continue }
            let body = await RichTextCache.shared.plainText(for: status)
            filterTexts[key] = body + " " + status.displayed.spoilerText
        }
    }

    private func decision(for status: Status) -> FilterEvaluator.Decision {
        let now = Date()
        if let expiry = nextFilterExpiry, now >= expiry {
            filterDecisions = [:]
            nextFilterExpiry = FilterEvaluator.nextExpiry(of: filters, after: now)
        }
        let key = FilterCacheKey(status)
        if let cached = filterDecisions[key] { return cached }
        let decided = FilterEvaluator.decision(
            for: status, filters: filters, context: filterContext, now: now,
            text: filterTexts[key])
        filterDecisions[key] = decided
        return decided
    }

    private var filterContext: FilterContext {
        switch key.source {
        case .home, .list: .home
        case .local, .federated, .hashtag, .trending: .public
        case .account, .profile: .account
        default: .home
        }
    }

    public func filterWarning(for status: Status) -> String? {
        guard case .warn(let title) = decision(for: status) else { return nil }
        return title
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
