// SPDX-License-Identifier: MIT

import AlohaDesign
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
        let store = AccountStore(modelContainer: StoreContainer.reader())
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
        let timelines = TimelineStore(modelContainer: StoreContainer.reader())
        // Only the rows the widget shows are read and decoded, not the whole
        // cached timeline: the widget's memory budget is a few megabytes.
        guard
            let statuses = try? await timelines.latestStatuses(
                accountID: accountID, timelineKey: "home:home", limit: limit)
        else { return [] }

        return statuses.map { status in
            let target = status.displayed
            return WidgetPost(
                id: target.id,
                accountID: accountID,
                author: target.account.bestDisplayName,
                handle: target.account.acct,
                text: target.spoilerText.isEmpty
                    ? plain(target.content) : target.spoilerText,
                createdAt: target.createdAt,
                // A tap from the widget outranks a cache that has not heard
                // about it yet.
                favourited: WidgetFavourites.state(statusID: target.id, accountID: accountID)
                    ?? target.favourited)
        }
    }

    /// What the account's Nextcloud said about its colour, from the
    /// capabilities the app persisted — a widget never asks the server.
    static func serverTheme(of snapshot: AccountStore.Snapshot) -> AlohaThemeModifier.ServerTheme? {
        guard let theme = snapshot.capabilities.theme, theme.hasColour else { return nil }
        return AlohaThemeModifier.ServerTheme(
            brightHex: theme.hex(onDarkBackground: false),
            darkHex: theme.hex(onDarkBackground: true),
            textHex: theme.textHex)
    }

    /// The colour of the account the app last had active.
    @MainActor
    static func activeServerTheme() async -> AlohaThemeModifier.ServerTheme? {
        await account(matching: WidgetAccount()).flatMap(serverTheme(of:))
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
        let container = StoreContainer.reader()
        var descriptor = FetchDescriptor<NotificationRecord>(
            predicate: #Predicate { $0.accountID == accountID && $0.kindRaw == "mention" },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        guard let records = try? container.mainContext.fetch(descriptor) else { return [] }

        let payloads = records.compactMap { record in
            (try? AlohaJSON.decoder.decode(NotificationPayload.self, from: record.payload))
                .map { (record, $0) }
        }
        // The notification does not say whether the post is favourited; the
        // cached post does, where the timeline has it.
        let cached =
            (try? await TimelineStore(modelContainer: container).statuses(
                accountID: accountID, ids: payloads.compactMap(\.1.statusID))) ?? [:]

        return payloads.compactMap { record, payload in
            guard !payload.title.isEmpty else { return nil }
            let favourited = payload.statusID.flatMap { id in
                WidgetFavourites.state(statusID: id, accountID: accountID)
                    ?? cached[id]?.displayed.favourited
            }
            return WidgetMention(
                id: record.serverID,
                accountID: accountID,
                author: payload.title,
                handle: payload.accountHandle,
                text: payload.body,
                createdAt: record.createdAt,
                statusID: payload.statusID,
                favourited: favourited ?? false)
        }
    }

    /// Today's "on this day", as the app last wrote it. A snapshot from
    /// another day is not today's, and is not shown.
    static func memories(now: Date = Date()) -> (MemoriesSnapshot, MemoriesSnapshotStore)? {
        guard let store = MemoriesSnapshotStore.shared, let snapshot = store.read(),
            snapshot.day == MemoriesSnapshot.dayKey(for: now)
        else { return nil }
        return (snapshot, store)
    }

    /// The link a row opens: the post, under the account it was read with, so
    /// a tap with another account active does not open somebody else's post
    /// with the same id.
    static func statusURL(accountID: UUID, statusID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "alohasocial"
        components.host = "status"
        components.path = "/\(accountID.uuidString)/\(statusID)"
        return components.url
    }

    private static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// What a widget button does, run in the extension's own process.
enum WidgetActions {
    enum Failure: Error {
        case noAccount, notSignedIn
    }

    /// Favourites or unfavourites one post with the token the app left in
    /// the shared Keychain group, and writes the answer back to the store so
    /// the app opens on what the widget did.
    @MainActor
    static func setFavourite(_ favourite: Bool, statusID: String, accountID: UUID) async throws {
        let container = StoreContainer.make()
        guard
            let snapshot = try await AccountStore(modelContainer: container).account(id: accountID)
        else { throw Failure.noAccount }
        guard let token = try CredentialStore.shared.token(for: accountID) else {
            throw Failure.notSignedIn
        }
        let client = APIClient(
            accountID: accountID, apiBase: snapshot.capabilities.apiBase, accessToken: token)
        let status = try await client.decode(
            Status.self,
            from: Endpoint.statuses.action(statusID, favourite ? .favourite : .unfavourite))
        try? await TimelineStore(modelContainer: container).updateStatus(
            accountID: accountID, status: status)
    }
}
