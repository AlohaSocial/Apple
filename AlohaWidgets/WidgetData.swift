// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaMedia
import AlohaModels
import AlohaNetwork
import AlohaStore
import CoreGraphics
import Foundation
import SwiftData

/// Reads the shared store. Deliberately narrow: the widget process has a tight
/// memory budget and must not stand up the app's whole object graph.
enum WidgetData {
    /// The account a Latest posts widget shows: the one picked, else the one
    /// a configuration from before the picker named by handle, else the
    /// account the app last had active.
    @MainActor
    static func account(matching configuration: WidgetAccount) async -> AccountStore.Snapshot? {
        if let picked = configuration.account?.id { return await account(id: picked) }
        guard let handle = configuration.handle, !handle.isEmpty else {
            return await account(id: nil)
        }
        let store = AccountStore(modelContainer: StoreContainer.reader())
        let snapshots = (try? await store.allAccounts()) ?? []
        return snapshots.first { $0.qualifiedHandle == handle } ?? activeAccount(in: snapshots)
    }

    /// One account by id, or the active one when there is no id or the
    /// account has since been removed.
    @MainActor
    static func account(id: UUID?) async -> AccountStore.Snapshot? {
        let store = AccountStore(modelContainer: StoreContainer.reader())
        guard let snapshots = try? await store.allAccounts() else { return nil }
        if let id, let match = snapshots.first(where: { $0.id == id }) { return match }
        return activeAccount(in: snapshots)
    }

    private static func activeAccount(
        in snapshots: [AccountStore.Snapshot]
    ) -> AccountStore.Snapshot? {
        let stored = AppGroup.defaults
            .string(forKey: AppGroup.activeAccountKey)
            .flatMap(UUID.init(uuidString:))
        return snapshots.first { $0.id == stored } ?? snapshots.first
    }

    /// The newest cached posts of one feed. Pictures come only from the app's
    /// disk cache: an avatar the app has not shown yet is a monogram here.
    @MainActor
    static func latestPosts(
        accountID: UUID, timelineKey: String, limit: Int, images: WidgetImages.Sizes
    ) async -> [WidgetPost] {
        let timelines = TimelineStore(modelContainer: StoreContainer.reader())
        // Only the rows the widget shows are read and decoded, not the whole
        // cached timeline: the widget's memory budget is a few megabytes.
        guard
            let statuses = try? await timelines.latestStatuses(
                accountID: accountID, timelineKey: timelineKey, limit: limit)
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
                    ?? target.favourited,
                avatar: images.avatar.flatMap { pixels in
                    target.account.preferredAvatarURL.flatMap {
                        WidgetImages.cached($0, pixels: pixels)
                    }
                },
                thumbnail: images.thumbnail.flatMap { pixels in
                    WidgetImages.thumbnailURL(of: target).flatMap {
                        WidgetImages.cached($0, pixels: pixels)
                    }
                })
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

    /// Every account's unread notifications together, or one account's when
    /// the widget is set to it. An account the app has not counted yet has
    /// nothing unread as far as the widget can know.
    static func unreadCount(accountID: UUID?) -> Int {
        guard let accountID else {
            return AppGroup.defaults.integer(forKey: AppGroup.unreadTotalKey)
        }
        let counts =
            AppGroup.defaults.dictionary(forKey: AppGroup.unreadByAccountKey) as? [String: Int]
        return counts?[accountID.uuidString] ?? 0
    }

    /// The newest mentions for one account, straight from the shared store.
    ///
    /// Mentions are the one notification kind that never groups (docs/05 §6),
    /// so a row is a row: a mention widget is a plain list rather than a
    /// count, and the newest few are what a person opens their phone to see.
    @MainActor
    static func latestMentions(
        accountID: UUID, limit: Int, avatarPixels: Int?
    ) async -> [WidgetMention] {
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
                favourited: favourited ?? false,
                avatar: avatarPixels.flatMap { pixels in
                    payload.avatarURL.flatMap { WidgetImages.cached($0, pixels: pixels) }
                })
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

/// Pictures for widget rows, from the disk cache the app fills as it shows
/// them (`ImageLoader`), shrunk on the way in (docs/09 §8).
enum WidgetImages {
    /// The decode sizes a family can use, in pixels; nil where it shows none.
    struct Sizes {
        var avatar: Int?
        var thumbnail: Int?

        static let none = Sizes(avatar: nil, thumbnail: nil)
    }

    static func cached(_ url: URL, pixels: Int) -> CGImage? {
        ImageLoader.cachedImage(for: url, maxPixels: pixels)
    }

    /// The first picture of a post, unless it is behind a warning: a Home
    /// Screen is a more public place than the app (as `MemoriesWidgetWriter`).
    static func thumbnailURL(of status: Status) -> URL? {
        guard !status.sensitive, status.spoilerText.isEmpty else { return nil }
        let image = status.mediaAttachments.first { $0.type == .image }
        return image?.previewURL ?? image?.url
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
