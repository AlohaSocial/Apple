// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import OSLog
import Observation

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

    private var tickTasks: [UUID: Task<Void, Never>] = [:]
    private var streams: [UUID: StreamingConnection] = [:]
    private var failureCounts: [UUID: Int] = [:]
    private var lastInteraction = Date()
    private var visibleTimelineLastSeen: [UUID: Date] = [:]

    private weak var environment: AppEnvironment?
    private let notifier: LocalNotifier
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "sync")

    public init(notifier: LocalNotifier = LocalNotifier()) {
        self.notifier = notifier
    }

    public func attach(to environment: AppEnvironment) {
        self.environment = environment
    }

    // MARK: - Lifecycle

    public func start() {
        guard let environment else { return }
        for session in environment.sessions { startTicking(session) }
    }

    public func stop() {
        for task in tickTasks.values { task.cancel() }
        tickTasks.removeAll()
        for stream in streams.values { stream.close() }
        streams.removeAll()
    }

    /// Called from a scene-phase change. A socket is closed on background
    /// immediately; polling stops and `BGAppRefreshTask` takes over.
    public func setForeground(_ isForeground: Bool) {
        if isForeground {
            noteInteraction()
            start()
        } else {
            stop()
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
        WidgetReloader.reloadAll()
        Task { await notifier.setBadge(total) }
    }

    public func noteTimelineVisible(for accountID: UUID) {
        visibleTimelineLastSeen[accountID] = Date()
    }

    private func startTicking(_ session: AccountSession) {
        tickTasks[session.id]?.cancel()

        // Nothing goes out for an account whose token was revoked.
        guard !session.needsReauthentication else { return }

        if let streamingURL = session.capabilities.streamingURL,
            let token = (try? environment?.credentials.token(for: session.id)) ?? nil
        {
            let connection = StreamingConnection(
                url: streamingURL, token: token,
                onEvent: { [weak self] event in
                    Task { @MainActor in await self?.handle(event, session: session) }
                })
            connection.open()
            streams[session.id] = connection
        }

        tickTasks[session.id] = Task { [weak self] in
            await self?.tickLoop(session)
        }
    }

    private func tickLoop(_ session: AccountSession) async {
        while !Task.isCancelled {
            let scheduler = currentScheduler(for: session)
            guard var interval = scheduler.interval else { return }

            // A live socket, or Nextcloud's push proxy delivering, makes
            // polling a safety net rather than the mechanism — neither is
            // trusted absolutely, because a socket can be silently dead and a
            // push can be dropped (docs/08 §6).
            if streams[session.id]?.isOpen == true { interval = max(interval, 300) }
            if session.isPushActive { interval = max(interval, 600) }

            // Backoff after failures, capped.
            if let failures = failureCounts[session.id], failures > 0 {
                interval = max(interval, Backoff.delay(attempt: failures))
            }

            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            await poll(session, scope: scheduler.scope)
        }
    }

    private func currentScheduler(for session: AccountSession) -> PollScheduler {
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
            isCellular: false,
            wifiOnlySync: false,
            frequency: session.settings.pollFrequency)
    }

    // MARK: - Polling

    @discardableResult
    public func poll(_ session: AccountSession, scope: PollScheduler.Scope = .full) async -> Int {
        guard !session.needsReauthentication else { return 0 }

        do {
            // Step one is the cheapest call there is, and it drives the badge.
            let count = try await fetchUnreadCount(session)
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

            if plan.wantsNotifications {
                await fetchAndAnnounceNotifications(session)
            }
            return count
        } catch {
            failureCounts[session.id, default: 0] += 1
            await session.handle(error)
            return unreadCounts[session.id] ?? 0
        }
    }

    private func fetchUnreadCount(_ session: AccountSession) async throws -> Int {
        let endpoint = Endpoint.notifications.unreadCount(
            grouped: session.capabilities.groupedNotifications)
        return try await session.client.decode(UnreadCount.self, from: endpoint).count
    }

    /// Announces at most once per server id; the raised set is persisted, so a
    /// poll cannot say the same thing twice (docs/08 §5).
    private func fetchAndAnnounceNotifications(_ session: AccountSession) async {
        do {
            let arrivals = try await NotificationSync.fetch(session: session)
            let fresh = try await session.supportStore.storeNotifications(
                arrivals, accountID: session.id)
            guard !fresh.isEmpty else { return }

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

            let announced = await notifier.announce(
                fresh,
                session: session,
                isQuiet: quiet.isQuiet(at: Date()),
                showAccountName: (environment?.sessions.count ?? 1) > 1)

            try await session.supportStore.markAnnounced(
                accountID: session.id, serverIDs: announced)
        } catch {
            await session.handle(error)
        }
    }

    // MARK: - Streaming

    private func handle(_ event: StreamingConnection.Event, session: AccountSession) async {
        switch event {
        case .update(let status):
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
    static func fetch(session: AccountSession) async throws -> [StoredNotification] {
        if session.capabilities.groupedNotifications {
            let results = try await session.client.decode(
                GroupedNotificationsResults.self,
                from: Endpoint.notifications.grouped(limit: 40))

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
            LossyArray<MastodonNotification>.self, from: Endpoint.notifications.flat(limit: 40))

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

/// What a stored notification carries so a local alert can be written without a
/// second fetch.
public struct NotificationPayload: Codable, Sendable, Hashable {
    public var title: String
    public var body: String
    public var avatarURL: URL?
    public var accountHandle: String
    public var statusID: String?

    static func encode(_ notification: MastodonNotification) -> Data {
        let payload = NotificationPayload(
            title: notification.account.bestDisplayName,
            body: Self.preview(notification.status),
            avatarURL: notification.account.preferredAvatarURL,
            accountHandle: notification.account.acct,
            statusID: notification.status?.id)
        return (try? AlohaJSON.encoder.encode(payload)) ?? Data()
    }

    static func encode(group: NotificationGroup, results: GroupedNotificationsResults) -> Data {
        let first = group.sampleAccountIDs.compactMap { results.account(id: $0) }.first
        let status = group.statusID.flatMap { results.status(id: $0) }
        let payload = NotificationPayload(
            title: first?.bestDisplayName ?? "",
            body: Self.preview(status),
            avatarURL: first?.preferredAvatarURL,
            accountHandle: first?.acct ?? "",
            statusID: group.statusID)
        return (try? AlohaJSON.encoder.encode(payload)) ?? Data()
    }

    public static func decode(_ data: Data) -> NotificationPayload? {
        try? AlohaJSON.decoder.decode(NotificationPayload.self, from: data)
    }

    private static func preview(_ status: Status?) -> String {
        guard let status else { return "" }
        let target = status.displayed
        if !target.spoilerText.isEmpty { return target.spoilerText }
        return target.content
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
