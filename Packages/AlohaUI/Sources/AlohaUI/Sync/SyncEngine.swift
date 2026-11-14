// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import OSLog
import Observation
import SwiftUI
import Synchronization

#if canImport(UIKit)
    import UIKit
#endif

/// Coordinates polling for every signed-in account.
///
/// Nextcloud Social serves no streaming API and no Web Push — and says so, with
/// an empty `urls` object and an empty `vapid_key`. So polling is the normal
/// case here rather than a degraded one, and the two upgrade paths sit on top
/// of it (docs/08 §2).
@MainActor
@Observable
public final class SyncEngine {
    public private(set) var unreadCounts: [UUID: Int] = [:]
    public private(set) var lastPoll: [UUID: Date] = [:]
    /// Bumped for an account whenever its home timeline is due a refresh: a
    /// poll that found the timeline recently visible, or a post arriving
    /// over the streaming socket. The timeline screen observes it and
    /// refreshes; the engine itself never writes timeline rows, so a post
    /// cannot land in the store without a place in the timeline.
    public private(set) var timelineRefreshRequests: [UUID: Int] = [:]

    /// Asks the visible home timeline of an account to refresh.
    func requestTimelineRefresh(for accountID: UUID) {
        guard isLive(accountID) else { return }
        timelineRefreshRequests[accountID, default: 0] &+= 1
    }

    /// The device's network path: polling pauses while there is none, and
    /// Wi-Fi-only sync reads whether it costs (docs/08 §3).
    public let network: NetworkConditions

    /// Whether some scene is in the foreground, so the loops should run.
    /// Set by `start()`, cleared by `stop()`.
    private(set) var isRunning = false
    @ObservationIgnored private var tickTasks: [UUID: Task<Void, Never>] = [:]
    /// The session each loop was started for. A renewed sign-in is a new
    /// session for the same account, and its loop must replace the old one
    /// rather than be mistaken for it.
    @ObservationIgnored private var tickSessions: [UUID: AccountSession] = [:]
    @ObservationIgnored private var streams: [UUID: StreamingConnection] = [:]
    @ObservationIgnored private var failureCounts: [UUID: Int] = [:]
    @ObservationIgnored private var lastInteraction = Date()
    @ObservationIgnored private var visibleTimelineLastSeen: [UUID: Date] = [:]
    /// Accounts whose server answered `notifications/unread_count` as a
    /// route it does not have. Their badge is counted from the notifications
    /// marker instead, without asking again until the next launch.
    @ObservationIgnored private(set) var unreadCountMissing: Set<UUID> = []
    /// Hosts that answered 429, and until when their polling runs at half
    /// the frequency (docs/08 §3).
    @ObservationIgnored private var slowedHosts: [String: Date] = [:]
    /// Scenes that are active or inactive. Sync runs while there is one.
    @ObservationIgnored private var foregroundScenes: Set<UUID> = []
    /// Accounts with a timeline refresh due from the socket, so a burst of
    /// posts asks once rather than once each.
    @ObservationIgnored private var pendingStreamRefreshes: Set<UUID> = []
    /// How long the socket's posts are gathered before the timeline is
    /// asked to refresh for them. A variable only so a test need not wait.
    @ObservationIgnored var streamRefreshDelay: Duration = .seconds(5)
    /// Accounts being removed, or removed. Nothing is fetched for them and
    /// nothing a fetch already under way brings back is written: the rows it
    /// would write are the ones the removal is deleting.
    @ObservationIgnored private var removedAccounts: Set<UUID> = []

    @ObservationIgnored private weak var environment: AppEnvironment?
    private let notifier: LocalNotifier
    private let logger = Logger(subsystem: "social.aloha.app", category: "sync")

    /// The least time between two polls of one account that a (re)start may
    /// leave. Every scene activation starts the engine, and a person
    /// flicking between apps would otherwise send a poll each time.
    static let minimumPromptGap: TimeInterval = 15
    /// How long a 429 halves the polling frequency for its host.
    static let rateLimitSlowdown: TimeInterval = 3600

    public init(notifier: LocalNotifier = LocalNotifier(), network: NetworkConditions? = nil) {
        self.notifier = notifier
        self.network = network ?? NetworkConditions()
    }

    public func attach(to environment: AppEnvironment) {
        self.environment = environment
    }

    // MARK: - Lifecycle

    /// Starts polling every account that is not polled already. Safe to call
    /// as often as anything likes: a loop already running for a session is
    /// left alone, so repeated starts neither stampede the server nor drop
    /// and reopen sockets.
    public func start() {
        guard let environment else { return }
        isRunning = true
        network.startMonitoring()
        // An account being removed is still in the list while its token is
        // revoked, and a scene activation in that time must not restart it.
        for session in environment.sessions where isLive(session.id) {
            ensureTicking(session)
        }
    }

    public func stop() {
        isRunning = false
        for task in tickTasks.values { task.cancel() }
        tickTasks.removeAll()
        tickSessions.removeAll()
        for stream in streams.values { Task { await stream.close() } }
        streams.removeAll()
    }

    /// Starts — or, for a renewed sign-in, restarts — polling for one
    /// session that has just been added or replaced. Nothing happens while
    /// the engine is stopped: the next start picks the session up.
    public func startPolling(_ session: AccountSession) {
        guard isRunning, isLive(session.id) else { return }
        ensureTicking(session)
    }

    /// Called from each scene's phase changes, with an id the scene keeps.
    ///
    /// Only the background stops anything. `.inactive` is Control Center,
    /// Face ID, a notification pulled down, another window of the app being
    /// focused on an iPad or a Mac — a moment, not a departure — and closing
    /// sockets for it meant every glance dropped sync and the badge then
    /// waited a full interval. With several windows, sync runs while any one
    /// of them is in the foreground and stops when the last one leaves; a
    /// socket closes then, immediately, and `BGAppRefreshTask` takes over
    /// (docs/08 §6).
    public func scene(_ scene: UUID, didEnter phase: ScenePhase) {
        switch phase {
        case .background:
            foregroundScenes.remove(scene)
        case .active:
            foregroundScenes.insert(scene)
            noteInteraction()
        default:
            foregroundScenes.insert(scene)
        }
        applySceneState()
    }

    /// A window closed. Its scene no longer holds sync up.
    public func sceneDidDisappear(_ scene: UUID) {
        guard foregroundScenes.remove(scene) != nil else { return }
        applySceneState()
    }

    private func applySceneState() {
        if foregroundScenes.isEmpty {
            if isRunning { stop() }
        } else {
            start()
        }
    }

    public func noteInteraction() {
        lastInteraction = Date()
    }

    /// The app group is where the widgets read it; `UserDefaults.standard`
    /// would be invisible to them.
    private func publishUnreadTotal() {
        let total = unreadCounts.values.reduce(0, +)
        AppGroup.defaults.set(total, forKey: AppGroup.unreadTotalKey)
        guard Self.isAppProcess else { return }
        WidgetReloader.reloadAll()
        #if os(iOS)
            // The watch face counts the paired account only, not the total.
            WatchBridge.shared.sendUnread(unreadCounts)
        #endif
        Task { await notifier.setBadge(total) }
    }

    /// Whether this process is an app or an extension, with widgets, a
    /// badge and a notification centre to tell. A package's test runner is
    /// neither: asking it for a notification centre raises an exception
    /// rather than failing, and its widget reloads go nowhere.
    private static let isAppProcess = ["app", "appex"].contains(
        Bundle.main.bundleURL.pathExtension)

    public func noteTimelineVisible(for accountID: UUID) {
        visibleTimelineLastSeen[accountID] = Date()
    }

    // MARK: - Removing an account

    /// Stops everything that runs for one account and forgets what it knew,
    /// before its rows are deleted.
    ///
    /// Until it did, a removed account went on polling and streaming until
    /// the app was backgrounded: each poll wrote its notifications back
    /// into the store the removal had just emptied, could raise them, and
    /// its unread count stayed in the badge. Returns once the account's
    /// poll loop has stopped, so a poll it had under way cannot write after
    /// the rows are gone.
    public func forget(_ accountID: UUID) async {
        removedAccounts.insert(accountID)
        let tick = tickTasks.removeValue(forKey: accountID)
        tickSessions[accountID] = nil
        tick?.cancel()
        if let stream = streams.removeValue(forKey: accountID) { await stream.close() }
        failureCounts[accountID] = nil
        lastPoll[accountID] = nil
        visibleTimelineLastSeen[accountID] = nil
        unreadCountMissing.remove(accountID)
        timelineRefreshRequests[accountID] = nil
        if unreadCounts.removeValue(forKey: accountID) != nil { publishUnreadTotal() }
        await tick?.value
    }

    /// Takes back an account whose removal failed, so it is polled again
    /// from the next start — its rows, and so the account, are still here.
    public func readmit(_ accountID: UUID) {
        removedAccounts.remove(accountID)
    }

    private func isLive(_ accountID: UUID) -> Bool {
        !removedAccounts.contains(accountID)
    }

    /// Whether a poll loop is running for an account, and for this very
    /// session of it.
    func isPolling(_ session: AccountSession) -> Bool {
        tickTasks[session.id] != nil && tickSessions[session.id] === session
    }

    private func ensureTicking(_ session: AccountSession) {
        if isPolling(session) { return }

        tickTasks.removeValue(forKey: session.id)?.cancel()
        tickSessions[session.id] = nil
        // The old session's socket carried the old token; a renewed session
        // opens its own.
        if let previous = streams.removeValue(forKey: session.id) {
            Task { await previous.close() }
        }

        // Nothing goes out for an account that is being removed. One whose
        // token was revoked keeps a loop, which waits for a fresh sign-in.
        guard isLive(session.id) else { return }

        if !session.needsReauthentication, let streamingURL = session.capabilities.streamingURL,
            let credentials = environment?.credentials,
            (try? credentials.token(for: session.id)) != nil
        {
            let accountID = session.id
            let connection = StreamingConnection(
                url: streamingURL,
                // Read on every connect, so a reconnect carries the token
                // the account has now rather than the one it opened with.
                token: { try? credentials.token(for: accountID) },
                onEvent: { [weak self] event in
                    Task { @MainActor in await self?.handle(event, session: session) }
                })
            Task { await connection.open() }
            streams[session.id] = connection
        }

        tickSessions[session.id] = session
        tickTasks[session.id] = Task { [weak self] in
            await self?.tickLoop(session)
        }
    }

    private func tickLoop(_ session: AccountSession) async {
        // The first poll after a start goes promptly. Sleeping a whole
        // interval first left the badge as it was for up to three minutes
        // after every launch and every return to the app.
        var isPrompt = true
        while !Task.isCancelled {
            // Signed out by the server: polling stops until a fresh sign-in
            // clears it (docs/08 §3).
            if session.needsReauthentication {
                await waitForChange { _ = session.needsReauthentication }
                isPrompt = true
                continue
            }
            // Offline: nothing to ask. Resumes on the path update rather
            // than on a timer (docs/08 §3).
            if !network.isSatisfied {
                await waitForChange { [network] in _ = network.isSatisfied }
                isPrompt = true
                continue
            }

            var streamIsOpen = false
            if let stream = streams[session.id] { streamIsOpen = await stream.isOpen }
            guard let interval = pollInterval(for: session, streamIsOpen: streamIsOpen) else {
                // Manual: no timer, until the setting changes back.
                await waitForChange { _ = session.settings.pollFrequency }
                isPrompt = true
                continue
            }

            let delay = isPrompt ? promptDelay(for: session, interval: interval) : interval
            isPrompt = false
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            // The network went while the loop slept: wait for it above
            // rather than spend a failure, and a backoff, on a poll that
            // could not have worked.
            guard network.isSatisfied else { continue }
            await poll(session, scope: currentScheduler(for: session).scope)
        }
    }

    /// The wait before the first poll after a start: none, unless the last
    /// one was moments ago or the account is backing off from failures.
    private func promptDelay(for session: AccountSession, interval: TimeInterval) -> TimeInterval {
        if (failureCounts[session.id] ?? 0) > 0 { return interval }
        guard let last = lastPoll[session.id] else { return 0 }
        let gap = min(Self.minimumPromptGap, interval)
        return max(0, gap - Date().timeIntervalSince(last))
    }

    /// The interval to the next poll of an account, or `nil` for none.
    func pollInterval(for session: AccountSession, streamIsOpen: Bool) -> TimeInterval? {
        guard var interval = currentScheduler(for: session).interval else { return nil }

        // A 429 halves the frequency for an hour, beyond whatever
        // `Retry-After` asked for (docs/08 §3).
        if isSlowedDown(session) { interval *= 2 }

        // A live socket, or Nextcloud's push proxy delivering, makes
        // polling a safety net rather than the mechanism — neither is
        // trusted absolutely, because a socket can be silently dead and a
        // push can be dropped (docs/08 §6).
        if streamIsOpen { interval = max(interval, 300) }
        if session.isPushActive { interval = max(interval, 600) }

        // Backoff after failures, capped.
        if let failures = failureCounts[session.id], failures > 0 {
            interval = max(interval, Backoff.delay(attempt: failures))
        }
        return interval
    }

    func isSlowedDown(_ session: AccountSession) -> Bool {
        guard let until = slowedHosts[Self.hostKey(session)] else { return false }
        return until > Date()
    }

    private static func hostKey(_ session: AccountSession) -> String {
        session.capabilities.apiBase.host()?.lowercased()
            ?? session.snapshot.instanceHost.lowercased()
    }

    /// Suspends until something `read` touches changes, or the task is
    /// cancelled. What a paused loop waits on: the network path, the
    /// polling frequency, the sign-in.
    private func waitForChange(_ read: @escaping () -> Void) async {
        let gate = ChangeGate()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.hold(continuation)
                withObservationTracking(read, onChange: { @Sendable in gate.open() })
            }
        } onCancel: {
            gate.open()
        }
    }

    func currentScheduler(for session: AccountSession) -> PollScheduler {
        let idle = Date().timeIntervalSince(lastInteraction)
        let activity: PollScheduler.Activity =
            idle < 120 ? .interacting : (idle < 600 ? .idleShort : .idleLong)

        var isLowPower = false
        #if canImport(UIKit)
            isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        #endif

        return PollScheduler(
            isActiveAccount: session.id == environment?.activeSession?.id,
            activity: activity,
            isLowPowerMode: isLowPower,
            isCellular: network.isCellular,
            wifiOnlySync: session.settings.syncOverWiFiOnly,
            frequency: session.settings.pollFrequency)
    }

    // MARK: - Polling

    @discardableResult
    public func poll(_ session: AccountSession, scope: PollScheduler.Scope = .full) async -> Int {
        guard !session.needsReauthentication, isLive(session.id) else { return 0 }

        do {
            // Step one is the cheapest call there is, and it drives the badge.
            let probe = try await probeUnread(session)
            // Removed while the request was out: the answer is nobody's now.
            guard isLive(session.id) else { return 0 }
            let count = probe.count
            let previous = unreadCounts[session.id]
            unreadCounts[session.id] = count
            lastPoll[session.id] = Date()
            failureCounts[session.id] = 0
            // Published wherever it changes, not only from background refresh —
            // a badge widget that only moves every fifteen minutes reads as broken.
            publishUnreadTotal()

            let timelineVisible =
                visibleTimelineLastSeen[session.id]
                .map { Date().timeIntervalSince($0) < 300 } ?? false

            let plan = PollPlan.make(
                scope: scope,
                timelineRecentlyVisible: timelineVisible,
                unreadCountChanged: previous != count)

            // The engine does not fetch the timeline itself: the screen
            // showing it does, anchored on what it has, so nothing lands
            // in the store without a place in it (docs/08 §9).
            if plan.wantsTimeline {
                requestTimelineRefresh(for: session.id)
            }
            if plan.wantsNotifications {
                if let arrivals = probe.arrivals {
                    // Counting them already fetched them.
                    await storeAndAnnounce(arrivals, session: session)
                } else {
                    await fetchAndAnnounceNotifications(session)
                }
            }
            return count
        } catch {
            guard isLive(session.id) else { return 0 }
            failureCounts[session.id, default: 0] += 1
            if let apiError = error as? APIError, case .rateLimited = apiError {
                slowedHosts[Self.hostKey(session)] = Date().addingTimeInterval(
                    Self.rateLimitSlowdown)
            }
            await session.handle(error)
            return unreadCounts[session.id] ?? 0
        }
    }

    /// What step one learned: the count, and — where the count had to be
    /// derived from the notifications themselves — what was fetched for it.
    private struct UnreadProbe {
        var count: Int
        var arrivals: [StoredNotification]?
    }

    private func probeUnread(_ session: AccountSession) async throws -> UnreadProbe {
        if !unreadCountMissing.contains(session.id) {
            do {
                return UnreadProbe(count: try await fetchUnreadCount(session), arrivals: nil)
            } catch let error as APIError where Self.meansRouteMissing(error) {
                // Mastodon before 4.3, GoToSocial, Akkoma and Pleroma have no
                // such route. Failing here used to mean notifications were
                // never fetched at all, and the poll only ever backed off.
                guard isLive(session.id) else { throw error }
                unreadCountMissing.insert(session.id)
                logger.notice("unread_count is not served; counting from the marker instead")
            }
        }
        return try await countSinceMarker(session)
    }

    /// Whether an error says the route is not there, rather than that this
    /// request failed. An HTML page where JSON was expected is a server
    /// answering a route it does not know with its front page.
    private static func meansRouteMissing(_ error: APIError) -> Bool {
        switch error {
        case .notFound, .decoding: true
        case .server(let status, _): status == 405 || status == 501
        default: false
        }
    }

    private func fetchUnreadCount(_ session: AccountSession) async throws -> Int {
        let endpoint = Endpoint.notifications.unreadCount(
            grouped: session.capabilities.groupedNotifications,
            types: Endpoint.notifications.everyType(
                onAlohaSocial: session.capabilities.isNextcloudSocial))
        return try await session.client.decode(UnreadCount.self, from: endpoint.failingFast())
            .count
    }

    /// The unread count where the server will not say it: the notifications
    /// newer than the notifications marker (docs/02 §7). The marker is the
    /// newer of the server's — another device may have read further — and
    /// the one kept here. One page is counted, so the count tops out at a
    /// page, much as the server's own does.
    private func countSinceMarker(_ session: AccountSession) async throws -> UnreadProbe {
        let local = try? await session.supportStore.marker(
            accountID: session.id, timeline: "notifications")
        // A server without markers still has notifications to count.
        let remote = try? await session.client.decode(
            MarkerSet.self, from: Endpoint.markers.read.failingFast()
        ).notifications?.lastReadID
        let marker: String? =
            switch (local, remote) {
            case (let local?, let remote?):
                SupportStore.isNewer(remote, than: local) ? remote : local
            case (let local?, nil): local
            case (nil, let remote): remote
            }
        let arrivals = try await NotificationSync.fetch(session: session, newerThan: marker)
        return UnreadProbe(count: arrivals.count, arrivals: arrivals)
    }

    /// Announces at most once per server id; the raised set is persisted, so a
    /// poll cannot say the same thing twice (docs/08 §5).
    private func fetchAndAnnounceNotifications(_ session: AccountSession) async {
        do {
            let arrivals = try await NotificationSync.fetch(session: session)
            await storeAndAnnounce(arrivals, session: session)
        } catch {
            guard isLive(session.id) else { return }
            await session.handle(error)
        }
    }

    private func storeAndAnnounce(
        _ arrivals: [StoredNotification], session: AccountSession
    ) async {
        do {
            // Each await is a moment the account may have been removed in;
            // what comes back after that is neither stored nor raised.
            guard isLive(session.id) else { return }
            let arrived = try await session.supportStore.storeNotifications(
                arrivals, accountID: session.id)
            // What quiet hours or a Focus held back on an earlier poll is
            // offered again with what just arrived, for the last twelve hours.
            let fresh = try await session.supportStore.pendingAnnouncements(
                arrived: arrived, accountID: session.id,
                since: Date().addingTimeInterval(-12 * 3600))
            guard !fresh.isEmpty, isLive(session.id) else { return }

            // Web Push, where a server has it, delivers the alert itself —
            // raising a local one too would show everything twice.
            guard session.capabilities.syncTier != .webPush else {
                try await session.supportStore.markAnnounced(
                    accountID: session.id, serverIDs: fresh.map(\.serverID))
                return
            }

            let quiet = QuietHours(
                startHour: session.settings.quietHoursStart,
                endHour: session.settings.quietHoursEnd)

            guard Self.isAppProcess else { return }
            let announced = await notifier.announce(
                fresh,
                session: session,
                isQuiet: quiet.isQuiet(at: Date()),
                showAccountName: (environment?.sessions.count ?? 1) > 1)

            guard isLive(session.id) else { return }
            try await session.supportStore.markAnnounced(
                accountID: session.id, serverIDs: announced)
        } catch {
            guard isLive(session.id) else { return }
            await session.handle(error)
        }
    }

    // MARK: - Streaming

    func handle(_ event: StreamingConnection.Event, session: AccountSession) async {
        // An event the socket delivered just before it was closed, or one
        // from the socket of a session a fresh sign-in has since replaced.
        guard isLive(session.id), tickSessions[session.id].map({ $0 === session }) ?? true
        else { return }
        switch event {
        case .update:
            // A new post has no place in the timeline yet, and writing it to
            // the store without one left it invisible until a sweep took it
            // away. The timeline fetches it instead, anchored on what it has
            // (docs/08 §9).
            scheduleStreamRefresh(for: session.id)
        case .edit(let status):
            // An edit keeps its place: rows already showing the post redraw.
            try? await session.timelineStore.updateStatus(accountID: session.id, status: status)
        case .delete(let id):
            try? await session.timelineStore.deleteStatus(accountID: session.id, serverID: id)
        case .notification:
            await fetchAndAnnounceNotifications(session)
        case .filtersChanged:
            await session.refreshServerState()
        case .closed:
            // A socket that gives up falls back to polling, which never stopped.
            streams[session.id] = nil
            logger.notice("streaming closed; polling continues")
        }
    }

    /// Asks the timeline to refresh for what the socket brought, once per
    /// burst: a busy home timeline delivers several posts a second.
    private func scheduleStreamRefresh(for accountID: UUID) {
        guard pendingStreamRefreshes.insert(accountID).inserted else { return }
        let delay = streamRefreshDelay
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            pendingStreamRefreshes.remove(accountID)
            requestTimelineRefresh(for: accountID)
        }
    }

    // MARK: - Background refresh

    /// Polls every account, raises what is new, and updates the badge. It does
    /// **not** fetch timelines: a background refresh exists to say something
    /// happened, not to warm a cache (docs/08 §4).
    public func performBackgroundRefresh() async -> Int {
        guard let environment else { return 0 }
        var total = 0
        for session in environment.sessions {
            total += await poll(session, scope: .notificationsOnly)
        }
        publishUnreadTotal()
        return total
    }
}

/// Reads whichever notification surface the server has.
enum NotificationSync {
    /// - Parameter newerThan: only what is newer than this notification —
    ///   the newest page of it, so a count from it and what is announced
    ///   from it are the latest rather than the oldest unread.
    static func fetch(
        session: AccountSession, newerThan: String? = nil
    ) async throws -> [StoredNotification] {
        let types = Endpoint.notifications.everyType(
            onAlohaSocial: session.capabilities.isNextcloudSocial)
        let anchor = newerThan.map(PageAnchor.immediatelyAfter) ?? .cold
        if session.capabilities.groupedNotifications {
            let results = try await session.client.decode(
                GroupedNotificationsResults.self,
                from: Endpoint.notifications.grouped(limit: 40, anchor: anchor, types: types)
                    .failingFast())

            return results.notificationGroups.map { group in
                StoredNotification(
                    serverID: group.groupKey,
                    isGroup: group.notificationsCount > 1,
                    kind: group.type,
                    createdAt: group.latestPageNotificationAt ?? Date(),
                    groupCount: group.notificationsCount,
                    payload: NotificationPayload.encode(group: group, results: results),
                    statusServerID: group.statusID)
            }
        }

        let page = try await session.client.decode(
            LossyArray<MastodonNotification>.self,
            from: Endpoint.notifications.flat(limit: 40, anchor: anchor, types: types)
                .failingFast())

        return page.elements.map { notification in
            StoredNotification(
                serverID: notification.id,
                isGroup: false,
                kind: notification.type,
                createdAt: notification.createdAt,
                groupCount: 1,
                payload: NotificationPayload.encode(notification),
                statusServerID: notification.status?.id)
        }
    }
}

/// One wake-up for a loop waiting on an observed change: opened by the
/// change or by cancellation, whichever comes first, and only once.
nonisolated private final class ChangeGate: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Void, Never>?
        var isOpen = false
    }
    private let state = Mutex(State())

    func hold(_ continuation: CheckedContinuation<Void, Never>) {
        let resumeNow = state.withLock { state in
            if state.isOpen { return true }
            state.continuation = continuation
            return false
        }
        if resumeNow { continuation.resume() }
    }

    func open() {
        let continuation = state.withLock { state in
            state.isOpen = true
            defer { state.continuation = nil }
            return state.continuation
        }
        continuation?.resume()
    }
}
