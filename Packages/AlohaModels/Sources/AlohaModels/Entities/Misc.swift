// SPDX-License-Identifier: MIT

import Foundation

public struct StatusContext: Codable, Sendable, Hashable {
    public var ancestors: [Status]
    public var descendants: [Status]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ancestors = (try? c.decode(LossyArray<Status>.self, forKey: .ancestors))?.elements ?? []
        descendants = (try? c.decode(LossyArray<Status>.self, forKey: .descendants))?.elements ?? []
    }

    public init(ancestors: [Status] = [], descendants: [Status] = []) {
        self.ancestors = ancestors
        self.descendants = descendants
    }

    enum CodingKeys: String, CodingKey { case ancestors, descendants }
}

public struct Tag: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    @LenientURL public var url: URL?
    public var history: [History]
    /// Present on the followed-tag and single-tag routes, absent from
    /// `/api/v1/trends/tags`, which is public and has no viewer to answer for.
    public var following: Bool?

    public var id: String { name.lowercased() }

    public struct History: Codable, Sendable, Hashable {
        public var day: String
        public var uses: String
        public var accounts: String

        public init(day: String, uses: String, accounts: String) {
            self.day = day
            self.uses = uses
            self.accounts = accounts
        }

        public var usesCount: Int { Int(uses) ?? 0 }
        public var accountsCount: Int { Int(accounts) ?? 0 }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        _url = try c.decode(LenientURL.self, forKey: .url)
        history = (try? c.decode(LossyArray<History>.self, forKey: .history))?.elements ?? []
        following = try c.decodeIfPresent(Bool.self, forKey: .following)
    }

    public init(name: String, url: URL? = nil, history: [History] = [], following: Bool? = nil) {
        self.name = name
        _url = .init(wrappedValue: url)
        self.history = history
        self.following = following
    }

    enum CodingKeys: String, CodingKey { case name, url, history, following }

    /// Nextcloud Social sends a single bucket and always `accounts: "0"` — it
    /// counts uses, not distinct accounts. A sparkline drawn from one point is
    /// a lie, and a participant count from a zero is another, so the UI shows
    /// uses only when this is true (docs/05 §7).
    public var hasOnlyOneBucket: Bool { history.count <= 1 }

    public var totalUses: Int { history.reduce(0) { $0 + $1.usesCount } }

    /// Normalisation matching `FollowedTagsRequest::normalise()`: no leading
    /// `#`, trimmed, lowercased, cut to the 127 characters the column holds.
    /// `#NextCloud` and `nextcloud` are one tag to follow, look up and unfollow.
    public static func normalise(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("#") { value.removeFirst() }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }
        return String(value.prefix(127))
    }
}

public struct Conversation: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var accounts: [Account]
    @LenientBool public var unread: Bool
    public var lastStatus: Status?

    enum CodingKeys: String, CodingKey {
        case id, accounts, unread
        case lastStatus = "last_status"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        accounts = (try? c.decode(LossyArray<Account>.self, forKey: .accounts))?.elements ?? []
        _unread = try c.decode(LenientBool.self, forKey: .unread)
        lastStatus = try? c.decodeIfPresent(Status.self, forKey: .lastStatus)
    }

    public init(
        id: String, accounts: [Account] = [], unread: Bool = false, lastStatus: Status? = nil
    ) {
        _id = .init(wrappedValue: id)
        self.accounts = accounts
        _unread = .init(wrappedValue: unread)
        self.lastStatus = lastStatus
    }
}

public struct Marker: Codable, Sendable, Hashable {
    @FlexibleID public var lastReadID: String
    @LenientInt public var version: Int
    public var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case version
        case lastReadID = "last_read_id"
        case updatedAt = "updated_at"
    }

    public init(lastReadID: String, version: Int = 0, updatedAt: Date? = nil) {
        _lastReadID = .init(wrappedValue: lastReadID)
        _version = .init(wrappedValue: version)
        self.updatedAt = updatedAt
    }
}

/// `GET /api/v1/markers` answers a JSON object keyed by timeline, `{}` for an
/// account with no markers yet — never `[]`.
public struct MarkerSet: Codable, Sendable, Hashable {
    public var home: Marker?
    public var notifications: Marker?

    public init(home: Marker? = nil, notifications: Marker? = nil) {
        self.home = home
        self.notifications = notifications
    }
}

public struct OAuthApplication: Codable, Sendable, Hashable {
    @FlexibleOptionalID public var id: String?
    public var name: String
    @LenientURL public var website: URL?
    public var clientID: String?
    public var clientSecret: String?
    public var redirectURI: String?
    /// Always present and always empty on Nextcloud Social: there is no Web Push
    /// endpoint, and that is the answer that makes a client stop asking.
    public var vapidKey: String?

    enum CodingKeys: String, CodingKey {
        case id, name, website
        case clientID = "client_id"
        case clientSecret = "client_secret"
        case redirectURI = "redirect_uri"
        case vapidKey = "vapid_key"
    }

    public init(
        id: String? = nil, name: String, website: URL? = nil, clientID: String? = nil,
        clientSecret: String? = nil, redirectURI: String? = nil, vapidKey: String? = nil
    ) {
        _id = .init(wrappedValue: id)
        self.name = name
        _website = .init(wrappedValue: website)
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.vapidKey = vapidKey
    }
}

public struct OAuthToken: Codable, Sendable, Hashable {
    public var accessToken: String
    public var tokenType: String
    public var scope: String
    public var createdAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case scope
        case accessToken = "access_token"
        case tokenType = "token_type"
        case createdAt = "created_at"
    }

    public init(
        accessToken: String, tokenType: String = "Bearer", scope: String = "",
        createdAt: TimeInterval? = nil
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.scope = scope
        self.createdAt = createdAt
    }
}

/// `/.well-known/oauth-authorization-server`.
public struct OAuthServerMetadata: Codable, Sendable, Hashable {
    @LenientURL public var authorizationEndpoint: URL?
    @LenientURL public var tokenEndpoint: URL?
    @LenientURL public var revocationEndpoint: URL?
    public var codeChallengeMethodsSupported: [String]?
    public var scopesSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case revocationEndpoint = "revocation_endpoint"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        case scopesSupported = "scopes_supported"
    }

    public init(
        authorizationEndpoint: URL? = nil, tokenEndpoint: URL? = nil,
        revocationEndpoint: URL? = nil,
        codeChallengeMethodsSupported: [String]? = nil, scopesSupported: [String]? = nil
    ) {
        _authorizationEndpoint = .init(wrappedValue: authorizationEndpoint)
        _tokenEndpoint = .init(wrappedValue: tokenEndpoint)
        _revocationEndpoint = .init(wrappedValue: revocationEndpoint)
        self.codeChallengeMethodsSupported = codeChallengeMethodsSupported
        self.scopesSupported = scopesSupported
    }

    public var supportsPKCE: Bool {
        codeChallengeMethodsSupported?.contains("S256") ?? true
    }
}

/// NodeInfo 2.0 / 2.1, served at the **true domain root** on Nextcloud Social
/// regardless of whether the client API rewrite is in place. That is what makes
/// it usable as the cross-check in API base discovery (docs/03 §2).
public struct NodeInfo: Codable, Sendable, Hashable {
    public var version: String
    public var software: Software
    public var protocols: [String]
    @LenientBool public var openRegistrations: Bool

    public struct Software: Codable, Sendable, Hashable {
        public var name: String
        public var version: String
        public var repository: String?
        public var homepage: String?

        public init(
            name: String, version: String, repository: String? = nil, homepage: String? = nil
        ) {
            self.name = name
            self.version = version
            self.repository = repository
            self.homepage = homepage
        }
    }

    enum CodingKeys: String, CodingKey {
        case version, software, protocols
        case openRegistrations = "openRegistrations"
    }

    public init(
        version: String, software: Software, protocols: [String] = [],
        openRegistrations: Bool = false
    ) {
        self.version = version
        self.software = software
        self.protocols = protocols
        _openRegistrations = .init(wrappedValue: openRegistrations)
    }
}

/// The document at `/.well-known/nodeinfo` naming where the real documents are.
public struct NodeInfoDirectory: Codable, Sendable, Hashable {
    public var links: [Link]
    public struct Link: Codable, Sendable, Hashable {
        public var rel: String
        @LenientURL public var href: URL?
        public init(rel: String, href: URL? = nil) {
            self.rel = rel
            _href = .init(wrappedValue: href)
        }
    }
    public init(links: [Link]) { self.links = links }
}

public struct Preferences: Codable, Sendable, Hashable {
    public var defaultVisibility: Visibility?
    @LenientBool public var defaultSensitive: Bool
    public var defaultLanguage: String?
    /// Real on Nextcloud Social, with PeerTube's three NSFW policies under
    /// Mastodon's names. A client that cannot read this guesses, which is how it
    /// ends up posting publicly for somebody whose default is followers-only.
    public var expandMedia: SensitiveMediaPolicy?
    @LenientBool public var expandSpoilers: Bool

    enum CodingKeys: String, CodingKey {
        case defaultVisibility = "posting:default:visibility"
        case defaultSensitive = "posting:default:sensitive"
        case defaultLanguage = "posting:default:language"
        case expandMedia = "reading:expand:media"
        case expandSpoilers = "reading:expand:spoilers"
    }

    public init(
        defaultVisibility: Visibility? = nil, defaultSensitive: Bool = false,
        defaultLanguage: String? = nil, expandMedia: SensitiveMediaPolicy? = nil,
        expandSpoilers: Bool = false
    ) {
        self.defaultVisibility = defaultVisibility
        _defaultSensitive = .init(wrappedValue: defaultSensitive)
        self.defaultLanguage = defaultLanguage
        self.expandMedia = expandMedia
        _expandSpoilers = .init(wrappedValue: expandSpoilers)
    }
}

public struct NotificationPolicy: Codable, Sendable, Hashable {
    public enum Decision: String, UnknownPreserving {
        case accept, filter, drop
        case unknownCase = "__unknown"
        public static func unknown(_ raw: String) -> Decision { .unknownCase }
        public var isUnknown: Bool { self == .unknownCase }
    }

    public var forNotFollowing: Decision
    public var forNotFollowers: Decision
    public var forNewAccounts: Decision
    public var forPrivateMentions: Decision
    public var forLimitedAccounts: Decision
    public var summary: Summary?

    public struct Summary: Codable, Sendable, Hashable {
        @LenientInt public var pendingRequestsCount: Int
        @LenientInt public var pendingNotificationsCount: Int
        enum CodingKeys: String, CodingKey {
            case pendingRequestsCount = "pending_requests_count"
            case pendingNotificationsCount = "pending_notifications_count"
        }
        public init(pendingRequestsCount: Int = 0, pendingNotificationsCount: Int = 0) {
            _pendingRequestsCount = .init(wrappedValue: pendingRequestsCount)
            _pendingNotificationsCount = .init(wrappedValue: pendingNotificationsCount)
        }
    }

    enum CodingKeys: String, CodingKey {
        case summary
        case forNotFollowing = "for_not_following"
        case forNotFollowers = "for_not_followers"
        case forNewAccounts = "for_new_accounts"
        case forPrivateMentions = "for_private_mentions"
        case forLimitedAccounts = "for_limited_accounts"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        forNotFollowing = try c.decodeIfPresent(Decision.self, forKey: .forNotFollowing) ?? .accept
        forNotFollowers = try c.decodeIfPresent(Decision.self, forKey: .forNotFollowers) ?? .accept
        forNewAccounts = try c.decodeIfPresent(Decision.self, forKey: .forNewAccounts) ?? .accept
        forPrivateMentions =
            try c.decodeIfPresent(Decision.self, forKey: .forPrivateMentions) ?? .accept
        forLimitedAccounts =
            try c.decodeIfPresent(Decision.self, forKey: .forLimitedAccounts) ?? .accept
        summary = try? c.decodeIfPresent(Summary.self, forKey: .summary)
    }

    public init(
        forNotFollowing: Decision = .accept, forNotFollowers: Decision = .accept,
        forNewAccounts: Decision = .accept, forPrivateMentions: Decision = .accept,
        forLimitedAccounts: Decision = .accept, summary: Summary? = nil
    ) {
        self.forNotFollowing = forNotFollowing
        self.forNotFollowers = forNotFollowers
        self.forNewAccounts = forNewAccounts
        self.forPrivateMentions = forPrivateMentions
        self.forLimitedAccounts = forLimitedAccounts
        self.summary = summary
    }
}

public struct NotificationRequest: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var createdAt: Date?
    public var updatedAt: Date?
    public var account: Account
    @LenientInt public var notificationsCount: Int
    public var lastStatus: Status?

    enum CodingKeys: String, CodingKey {
        case id, account
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case notificationsCount = "notifications_count"
        case lastStatus = "last_status"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        account = try c.decode(Account.self, forKey: .account)
        _notificationsCount = try c.decode(LenientInt.self, forKey: .notificationsCount)
        lastStatus = try? c.decodeIfPresent(Status.self, forKey: .lastStatus)
    }
}

public struct AccountList: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var title: String
    public var repliesPolicy: String?
    @LenientBool public var exclusive: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, exclusive
        case repliesPolicy = "replies_policy"
    }

    public init(id: String, title: String, repliesPolicy: String? = nil, exclusive: Bool = false) {
        _id = .init(wrappedValue: id)
        self.title = title
        self.repliesPolicy = repliesPolicy
        _exclusive = .init(wrappedValue: exclusive)
    }
}

public struct SearchResults: Codable, Sendable, Hashable {
    public var accounts: [Account]
    public var statuses: [Status]
    public var hashtags: [Tag]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = (try? c.decode(LossyArray<Account>.self, forKey: .accounts))?.elements ?? []
        statuses = (try? c.decode(LossyArray<Status>.self, forKey: .statuses))?.elements ?? []
        hashtags = (try? c.decode(LossyArray<Tag>.self, forKey: .hashtags))?.elements ?? []
    }

    public init(accounts: [Account] = [], statuses: [Status] = [], hashtags: [Tag] = []) {
        self.accounts = accounts
        self.statuses = statuses
        self.hashtags = hashtags
    }

    public var isEmpty: Bool { accounts.isEmpty && statuses.isEmpty && hashtags.isEmpty }

    enum CodingKeys: String, CodingKey { case accounts, statuses, hashtags }
}

public struct ScheduledStatus: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var scheduledAt: Date
    public var mediaAttachments: [MediaAttachment]
    public var params: Params

    public struct Params: Codable, Sendable, Hashable {
        public var text: String?
        public var visibility: Visibility?
        public var spoilerText: String?
        @LenientBool public var sensitive: Bool
        public var language: String?
        @FlexibleOptionalID public var inReplyToID: String?

        enum CodingKeys: String, CodingKey {
            case text, visibility, sensitive, language
            case spoilerText = "spoiler_text"
            case inReplyToID = "in_reply_to_id"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, params
        case scheduledAt = "scheduled_at"
        case mediaAttachments = "media_attachments"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        scheduledAt = try c.decodeIfPresent(Date.self, forKey: .scheduledAt) ?? Date()
        mediaAttachments =
            (try? c.decode(LossyArray<MediaAttachment>.self, forKey: .mediaAttachments))?.elements
            ?? []
        params = try c.decode(Params.self, forKey: .params)
    }
}

public struct FeaturedTag: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var name: String
    @LenientURL public var url: URL?
    @LenientInt public var statusesCount: Int
    public var lastStatusAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, url
        case statusesCount = "statuses_count"
        case lastStatusAt = "last_status_at"
    }
}

public struct Suggestion: Codable, Sendable, Hashable, Identifiable {
    public var source: String?
    public var sources: [String]?
    public var account: Account
    public var id: String { account.id }

    public init(account: Account, source: String? = nil, sources: [String]? = nil) {
        self.account = account
        self.source = source
        self.sources = sources
    }
}

public struct Announcement: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var content: String
    @LenientBool public var published: Bool
    @LenientBool public var read: Bool
    public var publishedAt: Date?
    public var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, content, published, read
        case publishedAt = "published_at"
        case updatedAt = "updated_at"
    }
}

/// The `Translation` entity behind `POST /api/v1/statuses/{id}/translate`.
public struct Translation: Codable, Sendable, Hashable {
    public var content: String
    public var spoilerText: String?
    public var detectedSourceLanguage: String?
    public var provider: String?

    enum CodingKeys: String, CodingKey {
        case content, provider
        case spoilerText = "spoiler_text"
        case detectedSourceLanguage = "detected_source_language"
    }

    public init(
        content: String, spoilerText: String? = nil,
        detectedSourceLanguage: String? = nil, provider: String? = nil
    ) {
        self.content = content
        self.spoilerText = spoilerText
        self.detectedSourceLanguage = detectedSourceLanguage
        self.provider = provider
    }
}

public struct StatusEdit: Codable, Sendable, Hashable {
    public var content: String
    public var spoilerText: String
    @LenientBool public var sensitive: Bool
    public var createdAt: Date
    public var account: Account
    public var mediaAttachments: [MediaAttachment]

    enum CodingKeys: String, CodingKey {
        case content, sensitive, account
        case spoilerText = "spoiler_text"
        case createdAt = "created_at"
        case mediaAttachments = "media_attachments"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        spoilerText = try c.decodeIfPresent(String.self, forKey: .spoilerText) ?? ""
        _sensitive = try c.decode(LenientBool.self, forKey: .sensitive)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        account = try c.decode(Account.self, forKey: .account)
        mediaAttachments =
            (try? c.decode(LossyArray<MediaAttachment>.self, forKey: .mediaAttachments))?.elements
            ?? []
    }
}

/// `GET /api/v1/statuses/{id}/source` — the original plain text, which is what
/// an edit composer must load rather than the rendered HTML (docs/07 §8).
public struct StatusSource: Codable, Sendable, Hashable {
    @FlexibleID public var id: String
    public var text: String
    public var spoilerText: String

    enum CodingKeys: String, CodingKey {
        case id, text
        case spoilerText = "spoiler_text"
    }
}

public struct UnreadCount: Codable, Sendable, Hashable {
    @LenientInt public var count: Int
    public init(count: Int) { _count = .init(wrappedValue: count) }
}
