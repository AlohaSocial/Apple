// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation

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

    private static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
