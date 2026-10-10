// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation
import SwiftData

/// Reads the shared store. Deliberately narrow: the widget process has a tight
/// memory budget and must not stand up the app's whole object graph.
enum WidgetData {
    @MainActor
    static func account(matching configuration: WidgetAccount) async -> AccountStore.Snapshot? {
        let store = AccountStore(modelContainer: StoreContainer.make())
        guard let snapshots = try? await store.allAccounts() else { return nil }
        if let handle = configuration.handle,
            let match = snapshots.first(where: { $0.qualifiedHandle == handle })
        {
            return match
        }
        let stored = AppGroup.defaults
            .string(forKey: AppGroup.activeAccountKey)
            .flatMap(UUID.init(uuidString:))
        return snapshots.first { $0.id == stored } ?? snapshots.first
    }

    @MainActor
    static func latestPosts(accountID: UUID, limit: Int) async -> [WidgetPost] {
        let timelines = TimelineStore(modelContainer: StoreContainer.make())
        guard
            let rows = try? await timelines.cachedTimeline(
                accountID: accountID, timelineKey: "home:home")
        else { return [] }

        return rows.compactMap(\.status).prefix(limit).map { status in
            let target = status.displayed
            return WidgetPost(
                id: target.id,
                author: target.account.bestDisplayName,
                handle: target.account.acct,
                text: target.spoilerText.isEmpty
                    ? plain(target.content) : target.spoilerText,
                createdAt: target.createdAt)
        }
    }

    @MainActor
    static func unreadCount() async -> Int {
        AppGroup.defaults.integer(forKey: AppGroup.unreadTotalKey)
    }

    /// The newest mentions for one account, straight from the shared store.
    ///
    /// Mentions are the one notification kind that never groups (docs/05 §6),
    /// so a row is a row: a mention widget is a plain list rather than a
    /// count, and the newest few are what a person opens their phone to see.
    @MainActor
    static func latestMentions(accountID: UUID, limit: Int) async -> [WidgetMention] {
        let container = StoreContainer.make()
        let descriptor = FetchDescriptor<NotificationRecord>(
            predicate: #Predicate { $0.accountID == accountID && $0.kindRaw == "mention" },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let records = try? container.mainContext.fetch(descriptor) else { return [] }

        return records.prefix(limit).compactMap { record in
            guard
                let payload = try? AlohaJSON.decoder.decode(
                    NotificationPayload.self, from: record.payload),
                !payload.title.isEmpty
            else { return nil }
            return WidgetMention(
                id: record.serverID,
                author: payload.title,
                handle: payload.accountHandle,
                text: payload.body,
                createdAt: record.createdAt,
                statusID: payload.statusID)
        }
    }

    private static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
