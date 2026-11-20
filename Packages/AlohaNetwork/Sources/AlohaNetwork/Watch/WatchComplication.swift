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
    /// Conversations with something unread, for the direct-messages
    /// complication; `nil` until a count has arrived, and in a snapshot an
    /// older build wrote.
    public var unreadConversations: Int?

    public init(
        accountID: UUID, unreadCount: Int?, mentions: [Mention], updatedAt: Date,
        unreadConversations: Int? = nil
    ) {
        self.accountID = accountID
        self.unreadCount = unreadCount
        self.mentions = mentions
        self.updatedAt = updatedAt
        self.unreadConversations = unreadConversations
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

    /// How often the watch app itself refreshes the snapshot on coming to
    /// the front. A glance at the app is often several in a minute — wrist
    /// up, wrist down, up again — and each used to cost a round of requests
    /// and three complication reloads for numbers seconds old.
    public static let appRefreshInterval: TimeInterval = 5 * 60

    /// Whether the watch app should ask the server again. The phone's
    /// pushed counts do not count as asking: they leave `updatedAt` alone.
    public static func appShouldRefresh(
        _ snapshot: WatchComplicationSnapshot?, at now: Date = Date()
    ) -> Bool {
        guard let snapshot else { return true }
        let age = now.timeIntervalSince(snapshot.updatedAt)
        // A clock that went backwards makes every snapshot look new.
        return age < 0 || age >= appRefreshInterval
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
    private static let userInfoConversationsKey = "aloha.complication.conversations"

    /// What the phone sends through `transferCurrentComplicationUserInfo`.
    /// Plist types only: WatchConnectivity refuses anything else. The
    /// conversation count rides along where the phone has one, so the
    /// direct-messages complication costs no transfer of its own.
    public static func unreadUserInfo(
        accountID: UUID, count: Int, conversations: Int? = nil
    ) -> [String: Any] {
        var info: [String: Any] = [
            userInfoAccountKey: accountID.uuidString, userInfoUnreadKey: count,
        ]
        if let conversations { info[userInfoConversationsKey] = conversations }
        return info
    }

    /// The counts in a received user info, if it is one of ours.
    public static func unreadUpdate(
        from userInfo: [String: Any]
    ) -> (accountID: UUID, count: Int, conversations: Int?)? {
        guard let raw = userInfo[userInfoAccountKey] as? String,
            let accountID = UUID(uuidString: raw),
            let count = userInfo[userInfoUnreadKey] as? Int
        else { return nil }
        return (accountID, count, userInfo[userInfoConversationsKey] as? Int)
    }

    /// This snapshot with a pushed count folded in. The mentions keep their
    /// own age: the push says nothing about them. A push without a
    /// conversation count leaves the one the snapshot has.
    public func applying(
        unreadCount count: Int, conversations: Int? = nil
    ) -> WatchComplicationSnapshot {
        var copy = self
        copy.unreadCount = count
        if let conversations { copy.unreadConversations = conversations }
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
        // Optional: a server that cannot say leaves the complication's dash
        // rather than failing the whole refresh.
        async let conversations = try? unreadConversations(client: client)
        return WatchComplicationSnapshot(
            accountID: accountID, unreadCount: try await count,
            mentions: try await mentions, updatedAt: now,
            unreadConversations: await conversations)
    }

    /// Conversations with something unread: the server's count, or where it
    /// has no such route (before Mastodon 4.3) the first page, counted.
    static func unreadConversations(client: APIClient) async throws -> Int {
        do {
            return try await client.decode(
                UnreadCount.self, from: Endpoint.timelines.conversationsUnreadCount
            ).count
        } catch APIError.notFound {
            return try await client.decode(
                LossyArray<Conversation>.self,
                from: Endpoint.timelines.conversations(limit: 40)
            ).elements.filter(\.unread).count
        }
    }

    /// The grouped count first, the flat one where a server has no v2 route.
    /// The watch has no capability probe of its own to ask which applies.
    ///
    /// Every type is named: Aloha Social leaves its own kinds (story
    /// reactions, tags, Bluesky) out of the count unless `types[]` asks for
    /// them, and Mastodon intersects the list with the kinds it knows.
    public static func unreadCount(client: APIClient) async throws -> Int {
        let types = Endpoint.notifications.everyType(onAlohaSocial: true)
        do {
            return try await client.decode(
                UnreadCount.self,
                from: Endpoint.notifications.unreadCount(grouped: true, types: types)
            ).count
        } catch APIError.notFound {
            return try await client.decode(
                UnreadCount.self,
                from: Endpoint.notifications.unreadCount(grouped: false, types: types)
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
    /// The direct messages list, which the unread-messages complication opens.
    case messages
    /// The notifications list, which the unread complication opens: it
    /// counts every kind, so it opens the list of every kind, not mentions.
    case notifications

    private static let scheme = "alohasocial"
    private static let host = "watch"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        switch self {
        case .mentions: components.path = "/mentions"
        case .status(let id): components.path = "/status/\(id)"
        case .messages: components.path = "/messages"
        case .notifications: components.path = "/notifications"
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
        case "messages" where parts.count == 1: self = .messages
        case "notifications" where parts.count == 1: self = .notifications
        case "status" where parts.count == 2 && !parts[1].isEmpty: self = .status(parts[1])
        default: return nil
        }
    }
}

// MARK: - Smart Stack relevance

/// The watch's complications, by their WidgetKit kind.
public enum WatchComplicationKind: String, Sendable, CaseIterable {
    case unread = "WatchUnread"
    case mentions = "WatchMentions"
    case directMessages = "WatchDirectMessages"
}

extension WatchComplicationSnapshot {
    /// How much a complication deserves the top of the Smart Stack, in
    /// WidgetKit's terms (`TimelineEntryRelevance`) without its import: this
    /// package is built for platforms that have no WidgetKit.
    public struct Relevance: Hashable, Sendable {
        public var score: Float
        /// Seconds the score holds; zero is "until the next entry".
        public var duration: TimeInterval

        public init(score: Float, duration: TimeInterval = 0) {
            self.score = score
            self.duration = duration
        }

        public static let none = Relevance(score: 0)
    }

    /// How long a new mention keeps the mentions complication up.
    public static let mentionRelevanceWindow: TimeInterval = 60 * 60

    /// Something waiting raises a complication; nothing waiting lets it
    /// sink. Messages rank above notifications, as on the phone's widgets:
    /// a message is written to one person, a favourite to nobody in
    /// particular. A mention ranks between them while it is new and the
    /// count says something is unread, and sinks after an hour.
    public func relevance(
        for kind: WatchComplicationKind, at now: Date = Date()
    ) -> Relevance {
        switch kind {
        case .directMessages:
            let unread = unreadConversations ?? 0
            return unread > 0 ? Relevance(score: 10 + Float(min(unread, 20))) : .none
        case .unread:
            let unread = unreadCount ?? 0
            return unread > 0 ? Relevance(score: 5 + Float(min(unread, 20))) : .none
        case .mentions:
            guard (unreadCount ?? 0) > 0, let newest = mentions.first else { return .none }
            let age = now.timeIntervalSince(newest.createdAt)
            guard (0..<Self.mentionRelevanceWindow).contains(age) else { return .none }
            return Relevance(score: 15, duration: Self.mentionRelevanceWindow - age)
        }
    }
}
