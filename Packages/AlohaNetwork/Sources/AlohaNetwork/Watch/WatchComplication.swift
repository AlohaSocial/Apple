// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// What the watch face shows: the unread count and the newest mentions of the
/// paired account.
///
/// Three writers keep it current, each for the case the others miss: the
/// watch app when it runs, the complication's own timeline when it is due
/// and the snapshot is stale, and the phone, which pushes the count it just
/// polled (`unreadUserInfo`). All of them write the same record to the watch's
/// app group, and the complications only ever draw from it.
public struct WatchComplicationSnapshot: Codable, Sendable, Hashable {
    public struct Mention: Codable, Sendable, Hashable, Identifiable {
        /// The notification's id.
        public var id: String
        public var author: String
        /// Plain text, or the content warning where the post has one: a
        /// complication is read in public, and a warning is there to be read
        /// first.
        public var text: String
        public var statusID: String?
        public var createdAt: Date

        public init(id: String, author: String, text: String, statusID: String?, createdAt: Date) {
            self.id = id
            self.author = author
            self.text = text
            self.statusID = statusID
            self.createdAt = createdAt
        }
    }

    public var accountID: UUID
    /// `nil` until a count has arrived; a face shows a dash, not a false zero.
    public var unreadCount: Int?
    public var mentions: [Mention]
    public var updatedAt: Date

    public init(accountID: UUID, unreadCount: Int?, mentions: [Mention], updatedAt: Date) {
        self.accountID = accountID
        self.unreadCount = unreadCount
        self.mentions = mentions
        self.updatedAt = updatedAt
    }

    public static let defaultsKey = "aloha.watchComplication"

    /// How old a snapshot may be before a timeline asks the server again.
    /// Fifteen minutes is about what watchOS grants a complication's
    /// refreshes anyway; asking more often only spends the budget.
    public static let refreshInterval: TimeInterval = 15 * 60

    /// How many mentions are kept: the largest face shows three.
    public static let mentionLimit = 3

    public func isStale(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(updatedAt) >= Self.refreshInterval
    }

    // MARK: - Storage

    /// The snapshot for `accountID`, or nil: a record left by an account the
    /// phone has since switched away from is not this account's news.
    public static func load(
        for accountID: UUID, from defaults: UserDefaults = AppGroup.defaults
    ) -> WatchComplicationSnapshot? {
        guard let data = defaults.data(forKey: defaultsKey),
            let snapshot = try? JSONDecoder().decode(Self.self, from: data),
            snapshot.accountID == accountID
        else { return nil }
        return snapshot
    }

    public func save(to defaults: UserDefaults = AppGroup.defaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    public static func clear(from defaults: UserDefaults = AppGroup.defaults) {
        defaults.removeObject(forKey: defaultsKey)
    }

    // MARK: - The phone's push

    private static let userInfoAccountKey = "aloha.complication.account"
    private static let userInfoUnreadKey = "aloha.complication.unread"

    /// What the phone sends through `transferCurrentComplicationUserInfo`.
    /// Plist types only: WatchConnectivity refuses anything else.
    public static func unreadUserInfo(accountID: UUID, count: Int) -> [String: Any] {
        [userInfoAccountKey: accountID.uuidString, userInfoUnreadKey: count]
    }

    /// The count in a received user info, if it is one of ours.
    public static func unreadUpdate(from userInfo: [String: Any]) -> (accountID: UUID, count: Int)?
    {
        guard let raw = userInfo[userInfoAccountKey] as? String,
            let accountID = UUID(uuidString: raw),
            let count = userInfo[userInfoUnreadKey] as? Int
        else { return nil }
        return (accountID, count)
    }

    /// This snapshot with a pushed count folded in. The mentions keep their
    /// own age: the push says nothing about them.
    public func applying(unreadCount count: Int) -> WatchComplicationSnapshot {
        var copy = self
        copy.unreadCount = count
        return copy
    }
}

/// Asks the server for what a complication shows.
public enum WatchComplicationRefresher {
    /// - Parameter plainText: HTML to plain text. Passed in because the
    ///   parser lives in AlohaHTML, which this package does not depend on.
    public static func fetch(
        client: APIClient, accountID: UUID, now: Date = Date(),
        plainText: @Sendable (String) -> String
    ) async throws -> WatchComplicationSnapshot {
        async let count = unreadCount(client: client)
        async let mentions = latestMentions(client: client, plainText: plainText)
        return WatchComplicationSnapshot(
            accountID: accountID, unreadCount: try await count,
            mentions: try await mentions, updatedAt: now)
    }

    /// The grouped count first, the flat one where a server has no v2 route.
    /// The watch has no capability probe of its own to ask which applies.
    static func unreadCount(client: APIClient) async throws -> Int {
        do {
            return try await client.decode(
                UnreadCount.self, from: Endpoint.notifications.unreadCount(grouped: true)
            ).count
        } catch APIError.notFound {
            return try await client.decode(
                UnreadCount.self, from: Endpoint.notifications.unreadCount(grouped: false)
            ).count
        }
    }

    static func latestMentions(
        client: APIClient, plainText: @Sendable (String) -> String
    ) async throws -> [WatchComplicationSnapshot.Mention] {
        let page = try await client.decode(
            LossyArray<MastodonNotification>.self,
            from: Endpoint.notifications.flat(limit: 10, types: ["mention"]))
        // Filtered here as well: a server that ignores `types` still answers
        // with every kind, and a favourite is not a mention.
        return page.elements
            .filter { $0.type == .mention }
            .prefix(WatchComplicationSnapshot.mentionLimit)
            .map { mention(from: $0, plainText: plainText) }
    }

    static func mention(
        from notification: MastodonNotification, plainText: (String) -> String
    ) -> WatchComplicationSnapshot.Mention {
        let status = notification.status
        let warning = status?.spoilerText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = warning.isEmpty ? (status.map { plainText($0.content) } ?? "") : warning
        return WatchComplicationSnapshot.Mention(
            id: notification.id, author: notification.account.bestDisplayName,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            statusID: status?.id, createdAt: notification.createdAt)
    }
}

/// The deep links a complication opens the watch app with.
public enum WatchComplicationLink: Hashable, Sendable {
    case mentions
    case status(String)

    private static let scheme = "alohasocial"
    private static let host = "watch"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        switch self {
        case .mentions: components.path = "/mentions"
        case .status(let id): components.path = "/status/\(id)"
        }
        // Every part is a fixed word or a server id; the fallback is only
        // there to keep the type non-optional.
        return components.url ?? URL(fileURLWithPath: "/")
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme, url.host() == Self.host else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch parts.first {
        case "mentions" where parts.count == 1: self = .mentions
        case "status" where parts.count == 2 && !parts[1].isEmpty: self = .status(parts[1])
        default: return nil
        }
    }
}
