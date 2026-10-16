// SPDX-License-Identifier: MIT

import Foundation

public struct Account: Codable, Sendable, Identifiable, Hashable {
    @FlexibleID public var id: String
    public var username: String
    /// `alice` for a local account, `alice@example.social` for a remote one.
    public var acct: String
    public var displayName: String
    public var note: String
    @LenientURL public var url: URL?
    @LenientURL public var uri: URL?
    /// May be `""` on Nextcloud Social. `LenientURL` turns that into `nil`
    /// rather than failing the whole account — see docs/04 §2.
    @LenientURL public var avatar: URL?
    @LenientURL public var avatarStatic: URL?
    @LenientURL public var header: URL?
    @LenientURL public var headerStatic: URL?
    @LenientBool public var locked: Bool
    @LenientBool public var bot: Bool
    @LenientBool public var discoverable: Bool
    @LenientBool public var suspended: Bool
    @LenientBool public var limited: Bool
    public var createdAt: Date?
    @LenientInt public var followersCount: Int
    @LenientInt public var followingCount: Int
    @LenientInt public var statusesCount: Int
    public var lastStatusAt: Date?
    public var fields: [Field]
    public var emojis: [CustomEmoji]
    /// Present only on the two credentials routes. Nextcloud Social used to emit
    /// it on every account, leaking `source.follow_requests_count`; it is now
    /// built by the routes that know they are answering the account itself.
    public var source: Source?
    public var moved: Box<Account>?

    public struct Field: Codable, Sendable, Hashable {
        public var name: String
        public var value: String
        public var verifiedAt: Date?
        public var isVerified: Bool { verifiedAt != nil }

        public init(name: String, value: String, verifiedAt: Date? = nil) {
            self.name = name
            self.value = value
            self.verifiedAt = verifiedAt
        }
    }

    public struct Source: Codable, Sendable, Hashable {
        public var note: String?
        public var fields: [Field]?
        public var privacy: Visibility?
        @LenientBool public var sensitive: Bool
        public var language: String?
        @LenientInt public var followRequestsCount: Int

        public init(
            note: String? = nil, fields: [Field]? = nil, privacy: Visibility? = nil,
            sensitive: Bool = false, language: String? = nil, followRequestsCount: Int = 0
        ) {
            self.note = note
            self.fields = fields
            self.privacy = privacy
            self.sensitive = sensitive
            self.language = language
            self.followRequestsCount = followRequestsCount
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, username, acct, note, url, uri, avatar, header, locked, bot
        case discoverable, suspended, limited, fields, emojis, source, moved
        case displayName = "display_name"
        case avatarStatic = "avatar_static"
        case headerStatic = "header_static"
        case createdAt = "created_at"
        case followersCount = "followers_count"
        case followingCount = "following_count"
        case statusesCount = "statuses_count"
        case lastStatusAt = "last_status_at"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        acct = try c.decodeIfPresent(String.self, forKey: .acct) ?? username
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        _url = try c.decode(LenientURL.self, forKey: .url)
        _uri = try c.decode(LenientURL.self, forKey: .uri)
        _avatar = try c.decode(LenientURL.self, forKey: .avatar)
        _avatarStatic = try c.decode(LenientURL.self, forKey: .avatarStatic)
        _header = try c.decode(LenientURL.self, forKey: .header)
        _headerStatic = try c.decode(LenientURL.self, forKey: .headerStatic)
        _locked = try c.decode(LenientBool.self, forKey: .locked)
        _bot = try c.decode(LenientBool.self, forKey: .bot)
        _discoverable = try c.decode(LenientBool.self, forKey: .discoverable)
        _suspended = try c.decode(LenientBool.self, forKey: .suspended)
        _limited = try c.decode(LenientBool.self, forKey: .limited)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        _followersCount = try c.decode(LenientInt.self, forKey: .followersCount)
        _followingCount = try c.decode(LenientInt.self, forKey: .followingCount)
        _statusesCount = try c.decode(LenientInt.self, forKey: .statusesCount)
        lastStatusAt = try c.decodeIfPresent(Date.self, forKey: .lastStatusAt)
        fields = (try? c.decode(LossyArray<Field>.self, forKey: .fields))?.elements ?? []
        emojis = (try? c.decode(LossyArray<CustomEmoji>.self, forKey: .emojis))?.elements ?? []
        source = try? c.decodeIfPresent(Source.self, forKey: .source)
        moved = try? c.decodeIfPresent(Box<Account>.self, forKey: .moved)
    }

    public init(
        id: String, username: String, acct: String, displayName: String = "", note: String = "",
        url: URL? = nil, uri: URL? = nil, avatar: URL? = nil, avatarStatic: URL? = nil,
        header: URL? = nil, headerStatic: URL? = nil, locked: Bool = false, bot: Bool = false,
        discoverable: Bool = true, suspended: Bool = false, limited: Bool = false,
        createdAt: Date? = nil, followersCount: Int = 0, followingCount: Int = 0,
        statusesCount: Int = 0, lastStatusAt: Date? = nil, fields: [Field] = [],
        emojis: [CustomEmoji] = [], source: Source? = nil, moved: Box<Account>? = nil
    ) {
        _id = .init(wrappedValue: id)
        self.username = username
        self.acct = acct
        self.displayName = displayName
        self.note = note
        _url = .init(wrappedValue: url)
        _uri = .init(wrappedValue: uri)
        _avatar = .init(wrappedValue: avatar)
        _avatarStatic = .init(wrappedValue: avatarStatic)
        _header = .init(wrappedValue: header)
        _headerStatic = .init(wrappedValue: headerStatic)
        _locked = .init(wrappedValue: locked)
        _bot = .init(wrappedValue: bot)
        _discoverable = .init(wrappedValue: discoverable)
        _suspended = .init(wrappedValue: suspended)
        _limited = .init(wrappedValue: limited)
        self.createdAt = createdAt
        _followersCount = .init(wrappedValue: followersCount)
        _followingCount = .init(wrappedValue: followingCount)
        _statusesCount = .init(wrappedValue: statusesCount)
        self.lastStatusAt = lastStatusAt
        self.fields = fields
        self.emojis = emojis
        self.source = source
        self.moved = moved
    }
}

extension Account {
    /// Prefer the non-animated representation for small UI chrome. Some
    /// servers publish an animated `avatar` whose first frame ImageIO cannot
    /// decode cheaply, while `avatar_static` is intended for exactly this use.
    public var preferredAvatarURL: URL? { avatarStatic ?? avatar }

    /// Headers follow the same convention as avatars.
    public var preferredHeaderURL: URL? { headerStatic ?? header }

    /// What a person reads. Never empty — falls back through the handle.
    public var bestDisplayName: String {
        displayName.isEmpty ? (username.isEmpty ? acct : username) : displayName
    }

    /// The host is shown only when it differs from the reader's own — which
    /// is what tells two Alices apart without cluttering every local post
    /// (docs/05 §3). A remote `acct` already carries its host; a local one has
    /// none and should not be given one.
    public func qualifiedHandle(localHost: String?) -> String {
        "@" + acct
    }

    public var host: String? {
        if let index = acct.firstIndex(of: "@") { return String(acct[acct.index(after: index)...]) }
        return url?.host()
    }
}

/// Indirection for a recursive `Codable` value (`Account.moved`, `Status.reblog`).
///
/// A struct cannot contain itself, even through a generic struct, so the
/// storage has to be a reference. `@unchecked Sendable` is safe here because
/// `Storage` is immutable and `Wrapped` is itself `Sendable`.
public struct Box<Wrapped: Codable & Sendable & Hashable>: Codable, Sendable, Hashable {
    private final class Storage: @unchecked Sendable {
        let value: Wrapped
        init(_ value: Wrapped) { self.value = value }
    }

    private let storage: Storage
    public var value: Wrapped { storage.value }

    public init(_ value: Wrapped) { storage = Storage(value) }

    public init(from decoder: any Decoder) throws {
        storage = Storage(try Wrapped(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws { try value.encode(to: encoder) }

    public static func == (lhs: Box, rhs: Box) -> Bool { lhs.value == rhs.value }
    public func hash(into hasher: inout Hasher) { hasher.combine(value) }
}
