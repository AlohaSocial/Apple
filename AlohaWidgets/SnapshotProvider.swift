// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaStore
import CoreGraphics
import Foundation
import WidgetKit

struct SnapshotEntry: WidgetKit.TimelineEntry {
    let date: Date
    /// The local account shown; nil before any account exists.
    let accountID: UUID?
    let accountHandle: String
    let snapshot: WidgetSnapshot?
    let images: [String: CGImage]
    let serverTheme: AlohaThemeModifier.ServerTheme?
    let relevance: TimelineEntryRelevance?

    static func empty(_ date: Date = Date()) -> SnapshotEntry {
        SnapshotEntry(
            date: date, accountID: nil, accountHandle: "", snapshot: nil, images: [:],
            serverTheme: nil, relevance: nil)
    }

    func image(_ file: String?) -> CGImage? { file.flatMap { images[$0] } }

    /// A screen of this account, for a tap.
    func url(_ host: String) -> URL? { SnapshotData.url(host, accountID: accountID) }

    func statusURL(_ statusID: String?) -> URL? {
        guard let accountID, let statusID else { return nil }
        return WidgetData.statusURL(accountID: accountID, statusID: statusID)
    }

    /// Unread messages raise the widget in a Smart Stack; none lets it sink.
    static func relevance(_ snapshot: WidgetSnapshot?) -> TimelineEntryRelevance {
        let unread = snapshot?.messages?.unread ?? 0
        return TimelineEntryRelevance(score: unread > 0 ? 10 + Float(min(unread, 20)) : 0)
    }
}

/// The Direct messages widget's provider: one account's snapshot, as the app
/// last wrote it (`WidgetSnapshotWriter`).
struct SnapshotProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        .empty()
    }

    func snapshot(
        for configuration: NotificationsWidgetAccount, in context: Context
    ) async -> SnapshotEntry {
        await entry(for: configuration, family: context.family)
    }

    /// The app reloads after every write, so this interval is only the floor.
    func timeline(
        for configuration: NotificationsWidgetAccount, in context: Context
    ) async -> Timeline<SnapshotEntry> {
        let entry = await entry(for: configuration, family: context.family)
        return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(900)))
    }

    @MainActor
    private func entry(
        for configuration: NotificationsWidgetAccount, family: WidgetFamily
    ) async -> SnapshotEntry {
        let now = Date()
        guard let loaded = await SnapshotData.load(accountID: configuration.account?.id) else {
            return .empty(now)
        }
        // Avatars only where rows are drawn: a count has no faces, and the
        // extension's memory budget is a few megabytes.
        var images: [String: CGImage] = [:]
        if family == .systemMedium || family == .systemLarge {
            for row in loaded.snapshot?.messages?.conversations ?? [] {
                guard let file = row.avatarFile else { continue }
                images[file] = SnapshotData.image(file, in: loaded.store, maxPixels: 64)
            }
        }
        return SnapshotEntry(
            date: now, accountID: loaded.account.id, accountHandle: loaded.account.qualifiedHandle,
            snapshot: loaded.snapshot, images: images, serverTheme: loaded.serverTheme,
            relevance: SnapshotEntry.relevance(loaded.snapshot))
    }
}
