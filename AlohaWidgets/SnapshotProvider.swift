// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaStore
import CoreGraphics
import Foundation
import WidgetKit

/// The widgets that show one account's snapshot and are configured by
/// account alone.
enum SnapshotWidgetKind {
    case directMessages, conversations, scheduled, requests, reports, weeklyStats
    case poll, dashboard, trends

    /// The kind string WidgetKit and the app's reloads know it by.
    var kind: String {
        switch self {
        case .directMessages: "DirectMessages"
        case .conversations: "Conversations"
        case .scheduled: "NextScheduledPost"
        case .requests: "Requests"
        case .reports: "OpenReports"
        case .weeklyStats: "WeeklyStats"
        case .poll: "LivePoll"
        case .dashboard: "CreatorDashboard"
        case .trends: "ServerTrends"
        }
    }

    /// The pictures this widget draws, decoded in the provider so the view
    /// does no file access.
    func pictures(in snapshot: WidgetSnapshot) -> [(file: String, pixels: Int)] {
        switch self {
        case .conversations:
            (snapshot.messages?.conversations ?? []).compactMap { row in
                row.avatarFile.map { ($0, 64) }
            }
        case .trends:
            (snapshot.trends?.links ?? []).compactMap { link in link.imageFile.map { ($0, 120) } }
        default:
            []
        }
    }

    /// How much this widget deserves the top of a Smart Stack right now:
    /// something waiting raises it, nothing waiting lets it sink.
    func relevance(_ snapshot: WidgetSnapshot?, now: Date) -> TimelineEntryRelevance? {
        guard let snapshot else { return TimelineEntryRelevance(score: 0) }
        switch self {
        case .directMessages, .conversations:
            let unread = snapshot.messages?.unread ?? 0
            return TimelineEntryRelevance(score: unread > 0 ? 10 + Float(min(unread, 20)) : 0)
        case .requests:
            let waiting = (snapshot.followRequests ?? 0) + (snapshot.notificationRequests ?? 0)
            return TimelineEntryRelevance(score: waiting > 0 ? 5 + Float(min(waiting, 20)) : 0)
        case .reports:
            let open = snapshot.openReports ?? 0
            return TimelineEntryRelevance(score: open > 0 ? 8 + Float(min(open, 20)) : 0)
        case .scheduled:
            guard let next = snapshot.scheduled?.first(where: { $0.at > now }) else {
                return TimelineEntryRelevance(score: 0)
            }
            let wait = next.at.timeIntervalSince(now)
            // The hour before a post goes out is when its countdown matters.
            if wait < 3600 { return TimelineEntryRelevance(score: 30, duration: wait + 600) }
            return TimelineEntryRelevance(score: wait < 86_400 ? 4 : 1)
        case .poll:
            guard let poll = snapshot.poll else { return TimelineEntryRelevance(score: 0) }
            if poll.isClosed(at: now) { return TimelineEntryRelevance(score: 1) }
            if let closes = poll.expiresAt, closes.timeIntervalSince(now) < 3 * 3600 {
                return TimelineEntryRelevance(
                    score: 20, duration: closes.timeIntervalSince(now))
            }
            return TimelineEntryRelevance(score: 5)
        case .weeklyStats, .dashboard, .trends:
            return TimelineEntryRelevance(score: 1)
        }
    }

    /// When to read the snapshot again without being told: the app reloads
    /// after every write, so this is only the floor — or the moment a
    /// scheduled post or a poll changes on its own.
    func nextReload(_ snapshot: WidgetSnapshot?, now: Date) -> Date {
        let floor = now.addingTimeInterval(900)
        switch self {
        case .scheduled:
            guard let next = snapshot?.scheduled?.first(where: { $0.at > now }) else {
                return floor
            }
            return min(floor, next.at.addingTimeInterval(60))
        case .poll:
            guard let closes = snapshot?.poll?.expiresAt, closes > now else { return floor }
            return min(floor, closes.addingTimeInterval(60))
        default:
            return floor
        }
    }
}

struct SnapshotEntry: WidgetKit.TimelineEntry {
    let date: Date
    /// The local account shown; nil before any account exists.
    let accountID: UUID?
    let accountHandle: String
    let snapshot: WidgetSnapshot?
    let drafts: Int
    let images: [String: CGImage]
    let serverTheme: AlohaThemeModifier.ServerTheme?
    let relevance: TimelineEntryRelevance?

    static func empty(_ date: Date = Date()) -> SnapshotEntry {
        SnapshotEntry(
            date: date, accountID: nil, accountHandle: "", snapshot: nil, drafts: 0, images: [:],
            serverTheme: nil, relevance: nil)
    }

    func image(_ file: String?) -> CGImage? { file.flatMap { images[$0] } }

    /// A screen of this account, for a tap.
    func url(_ host: String) -> URL? { SnapshotData.url(host, accountID: accountID) }

    func statusURL(_ statusID: String?) -> URL? {
        guard let accountID, let statusID else { return nil }
        return WidgetData.statusURL(accountID: accountID, statusID: statusID)
    }
}

/// One provider for every account-configured snapshot widget, told apart by
/// its kind.
struct SnapshotProvider: AppIntentTimelineProvider {
    let kind: SnapshotWidgetKind

    func placeholder(in context: Context) -> SnapshotEntry {
        .empty()
    }

    func snapshot(
        for configuration: NotificationsWidgetAccount, in context: Context
    ) async -> SnapshotEntry {
        await entry(for: configuration)
    }

    func timeline(
        for configuration: NotificationsWidgetAccount, in context: Context
    ) async -> Timeline<SnapshotEntry> {
        let entry = await entry(for: configuration)
        return Timeline(
            entries: [entry], policy: .after(kind.nextReload(entry.snapshot, now: entry.date)))
    }

    @MainActor
    private func entry(for configuration: NotificationsWidgetAccount) async -> SnapshotEntry {
        let now = Date()
        guard let loaded = await SnapshotData.load(accountID: configuration.account?.id) else {
            return .empty(now)
        }
        var images: [String: CGImage] = [:]
        for picture in loaded.snapshot.map(kind.pictures(in:)) ?? [] {
            images[picture.file] = SnapshotData.image(
                picture.file, in: loaded.store, maxPixels: picture.pixels)
        }
        return SnapshotEntry(
            date: now, accountID: loaded.account.id, accountHandle: loaded.account.qualifiedHandle,
            snapshot: loaded.snapshot,
            drafts: kind == .dashboard ? SnapshotData.draftCount(accountID: loaded.account.id) : 0,
            images: images, serverTheme: loaded.serverTheme,
            relevance: kind.relevance(loaded.snapshot, now: now))
    }
}
