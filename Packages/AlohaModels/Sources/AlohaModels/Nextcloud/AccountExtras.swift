// SPDX-License-Identifier: MIT

import Foundation

// The account-side surfaces Nextcloud Social serves beyond Mastodon's client
// API: authorized apps, the portfolio page, migration, statistics, channels.
// Every entity decodes leniently, as the rest of the models do (docs/04 §2).

/// One application that holds a token for the viewer's account.
public struct AuthorizedApp: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var name: String
    @LenientURL public var website: URL?
    public var createdAt: Date?
    public var signedIn: Date?
    public var lastUsedAt: Date?
    public var scopes: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, website, scopes
        case createdAt = "created_at"
        case signedIn = "signed_in"
        case lastUsedAt = "last_used_at"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        _website = try c.decode(LenientURL.self, forKey: .website)
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        signedIn = try? c.decodeIfPresent(Date.self, forKey: .signedIn)
        lastUsedAt = try? c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        // Sent as an array by the app and as one space-separated string by
        // the OAuth layer; both are the same list.
        if let list = try? c.decode([String].self, forKey: .scopes) {
            scopes = list
        } else if let joined = try? c.decode(String.self, forKey: .scopes) {
            scopes = joined.split(separator: " ").map(String.init)
        } else {
            scopes = []
        }
    }

    public init(
        id: String, name: String, website: URL? = nil, createdAt: Date? = nil,
        signedIn: Date? = nil, lastUsedAt: Date? = nil, scopes: [String] = []
    ) {
        _id = .init(wrappedValue: id)
        self.name = name
        _website = .init(wrappedValue: website)
        self.createdAt = createdAt
        self.signedIn = signedIn
        self.lastUsedAt = lastUsedAt
        self.scopes = scopes
    }
}

/// A name alone, which is what `/featured_tags/suggestions` sends.
public struct FeaturedTagSuggestion: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var id: String { name }

    public init(name: String) { self.name = name }
}

// MARK: - Portfolio

/// Where a portfolio picture was taken, when the post carried a place.
public struct PortfolioPlace: Codable, Sendable, Hashable {
    public var name: String?
    public var country: String?

    public init(name: String? = nil, country: String? = nil) {
        self.name = name
        self.country = country
    }
}

/// One picture on a portfolio page. A status, reduced to what the page shows.
public struct PortfolioPost: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var content: String?
    public var createdAt: Date?
    @LenientURL public var url: URL?
    public var mediaAttachments: [MediaAttachment]
    public var place: PortfolioPlace?

    enum CodingKeys: String, CodingKey {
        case id, content, url, place
        case createdAt = "created_at"
        case mediaAttachments = "media_attachments"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        content = try? c.decodeIfPresent(String.self, forKey: .content)
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        _url = try c.decode(LenientURL.self, forKey: .url)
        mediaAttachments =
            (try? c.decode(LossyArray<MediaAttachment>.self, forKey: .mediaAttachments))?.elements
            ?? []
        place = try? c.decodeIfPresent(PortfolioPlace.self, forKey: .place)
    }

    public init(
        id: String, content: String? = nil, createdAt: Date? = nil, url: URL? = nil,
        mediaAttachments: [MediaAttachment] = [], place: PortfolioPlace? = nil
    ) {
        _id = .init(wrappedValue: id)
        self.content = content
        self.createdAt = createdAt
        _url = .init(wrappedValue: url)
        self.mediaAttachments = mediaAttachments
        self.place = place
    }

    /// The first picture, which is what a portfolio shows.
    public var picture: MediaAttachment? {
        mediaAttachments.first { $0.type == .image } ?? mediaAttachments.first
    }
}

/// The viewer's own portfolio settings, as `GET/POST /api/v1.1/portfolio`
/// exchange them.
public struct PortfolioSettings: Codable, Sendable, Hashable {
    public enum Layout: String, Codable, Sendable, Hashable, CaseIterable {
        case grid, rows
    }
    public enum Source: String, Codable, Sendable, Hashable, CaseIterable {
        case recent, collection
    }

    @LenientBool public var active: Bool
    public var title: String
    public var intro: String
    public var layout: Layout
    public var source: Source
    @FlexibleOptionalID public var collectionID: String?
    @LenientBool public var showCaptions: Bool
    @LenientBool public var showPlaces: Bool
    @LenientBool public var showDates: Bool
    @LenientBool public var showAvatar: Bool
    @LenientURL public var url: URL?
    /// The pictures the page would show, where the server sends them along.
    public var posts: [PortfolioPost]

    enum CodingKeys: String, CodingKey {
        case active, title, intro, layout, source, url, posts
        case collectionID = "collection_id"
        case showCaptions = "show_captions"
        case showPlaces = "show_places"
        case showDates = "show_dates"
        case showAvatar = "show_avatar"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _active = try c.decode(LenientBool.self, forKey: .active)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        intro = (try? c.decodeIfPresent(String.self, forKey: .intro)) ?? ""
        layout = (try? c.decodeIfPresent(Layout.self, forKey: .layout)) ?? .grid
        source = (try? c.decodeIfPresent(Source.self, forKey: .source)) ?? .recent
        _collectionID = try c.decode(FlexibleOptionalID.self, forKey: .collectionID)
        _showCaptions = try c.decode(LenientBool.self, forKey: .showCaptions)
        _showPlaces = try c.decode(LenientBool.self, forKey: .showPlaces)
        _showDates = try c.decode(LenientBool.self, forKey: .showDates)
        _showAvatar = try c.decode(LenientBool.self, forKey: .showAvatar)
        _url = try c.decode(LenientURL.self, forKey: .url)
        posts = (try? c.decode(LossyArray<PortfolioPost>.self, forKey: .posts))?.elements ?? []
    }

    public init(
        active: Bool = false, title: String = "", intro: String = "", layout: Layout = .grid,
        source: Source = .recent, collectionID: String? = nil, showCaptions: Bool = true,
        showPlaces: Bool = true, showDates: Bool = true, showAvatar: Bool = true,
        url: URL? = nil, posts: [PortfolioPost] = []
    ) {
        _active = .init(wrappedValue: active)
        self.title = title
        self.intro = intro
        self.layout = layout
        self.source = source
        _collectionID = .init(wrappedValue: collectionID)
        _showCaptions = .init(wrappedValue: showCaptions)
        _showPlaces = .init(wrappedValue: showPlaces)
        _showDates = .init(wrappedValue: showDates)
        _showAvatar = .init(wrappedValue: showAvatar)
        _url = .init(wrappedValue: url)
        self.posts = posts
    }
}

/// A published portfolio page, readable by anybody with the address.
public struct PortfolioPage: Codable, Sendable, Hashable {
    public var title: String
    public var intro: String?
    public var handle: String?
    @LenientURL public var avatar: URL?
    public var layout: PortfolioSettings.Layout
    @LenientBool public var showCaptions: Bool
    @LenientBool public var showPlaces: Bool
    @LenientBool public var showDates: Bool
    @LenientBool public var showAvatar: Bool
    public var posts: [PortfolioPost]

    enum CodingKeys: String, CodingKey {
        case title, intro, handle, avatar, layout, posts
        case showCaptions = "show_captions"
        case showPlaces = "show_places"
        case showDates = "show_dates"
        case showAvatar = "show_avatar"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        intro = try? c.decodeIfPresent(String.self, forKey: .intro)
        handle = try? c.decodeIfPresent(String.self, forKey: .handle)
        _avatar = try c.decode(LenientURL.self, forKey: .avatar)
        layout = (try? c.decodeIfPresent(PortfolioSettings.Layout.self, forKey: .layout)) ?? .grid
        // Absent means shown: the page defaults are the generous ones.
        _showCaptions = LenientBool(
            wrappedValue: (try? c.decodeIfPresent(LenientBool.self, forKey: .showCaptions))??
                .wrappedValue ?? true)
        _showPlaces = LenientBool(
            wrappedValue: (try? c.decodeIfPresent(LenientBool.self, forKey: .showPlaces))??
                .wrappedValue ?? true)
        _showDates = LenientBool(
            wrappedValue: (try? c.decodeIfPresent(LenientBool.self, forKey: .showDates))??
                .wrappedValue ?? true)
        _showAvatar = LenientBool(
            wrappedValue: (try? c.decodeIfPresent(LenientBool.self, forKey: .showAvatar))??
                .wrappedValue ?? true)
        posts = (try? c.decode(LossyArray<PortfolioPost>.self, forKey: .posts))?.elements ?? []
    }

    public init(
        title: String, intro: String? = nil, handle: String? = nil, avatar: URL? = nil,
        layout: PortfolioSettings.Layout = .grid, showCaptions: Bool = true,
        showPlaces: Bool = true, showDates: Bool = true, showAvatar: Bool = true,
        posts: [PortfolioPost] = []
    ) {
        self.title = title
        self.intro = intro
        self.handle = handle
        _avatar = .init(wrappedValue: avatar)
        self.layout = layout
        _showCaptions = .init(wrappedValue: showCaptions)
        _showPlaces = .init(wrappedValue: showPlaces)
        _showDates = .init(wrappedValue: showDates)
        _showAvatar = .init(wrappedValue: showAvatar)
        self.posts = posts
    }
}

// MARK: - Migration

public struct MigrationAliases: Codable, Sendable, Hashable {
    public var aliases: [String]

    public init(aliases: [String]) { self.aliases = aliases }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aliases = (try? c.decode([String].self, forKey: .aliases)) ?? []
    }
}

/// What to paste into the old server's "move to" box.
public struct MigrationAnnouncement: Codable, Sendable, Hashable {
    public var handle: String
    public var address: String

    public init(handle: String, address: String) {
        self.handle = handle
        self.address = address
    }
}

/// Handles pulled out of an Instagram archive.
public struct MigrationHandles: Codable, Sendable, Hashable {
    public var handles: [String]

    public init(handles: [String]) { self.handles = handles }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        handles = (try? c.decode([String].self, forKey: .handles)) ?? []
    }
}

/// Which of those handles exist somewhere. The server has sent this in two
/// shapes; both are read.
public struct MigrationLookup: Sendable, Hashable, Decodable {
    public struct Entry: Sendable, Hashable, Identifiable {
        public var handle: String
        public var found: Bool
        public var account: Account?
        public var id: String { handle }

        public init(handle: String, found: Bool, account: Account? = nil) {
            self.handle = handle
            self.found = found
            self.account = account
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry]) { self.entries = entries }

    private struct RawEntry: Decodable {
        var handle: String?
        var acct: String?
        var found: LenientBool?
        var account: Account?
    }

    private enum CodingKeys: String, CodingKey {
        case results, found, missing, accounts
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var entries: [Entry] = []
        if let results = try? c.decode(LossyArray<RawEntry>.self, forKey: .results) {
            for raw in results.elements {
                let handle = raw.handle ?? raw.acct ?? raw.account?.acct ?? ""
                guard !handle.isEmpty else { continue }
                entries.append(
                    Entry(
                        handle: handle, found: raw.found?.wrappedValue ?? (raw.account != nil),
                        account: raw.account))
            }
        }
        if let found = try? c.decode(LossyArray<Account>.self, forKey: .found) {
            entries += found.elements.map { Entry(handle: $0.acct, found: true, account: $0) }
        } else if let found = try? c.decode([String].self, forKey: .found) {
            entries += found.map { Entry(handle: $0, found: true) }
        }
        if let accounts = try? c.decode(LossyArray<Account>.self, forKey: .accounts) {
            entries += accounts.elements.map { Entry(handle: $0.acct, found: true, account: $0) }
        }
        if let missing = try? c.decode([String].self, forKey: .missing) {
            entries += missing.map { Entry(handle: $0, found: false) }
        }
        var seen = Set<String>()
        self.entries = entries.filter { seen.insert($0.handle).inserted }
    }
}

/// A server's account of what an import did. The keys vary by kind
/// (`followed`, `skipped`, `imported`, …) so they are kept as they came.
public struct MigrationReport: Sendable, Hashable, Decodable {
    public var lines: [(key: String, value: String)]
    public var log: [String]

    public static func == (lhs: MigrationReport, rhs: MigrationReport) -> Bool {
        lhs.lines.map(\.key) == rhs.lines.map(\.key)
            && lhs.lines.map(\.value) == rhs.lines.map(\.value) && lhs.log == rhs.log
    }

    public func hash(into hasher: inout Hasher) {
        for line in lines {
            hasher.combine(line.key)
            hasher.combine(line.value)
        }
        hasher.combine(log)
    }

    public init(lines: [(key: String, value: String)] = [], log: [String] = []) {
        self.lines = lines
        self.log = log
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        var lines: [(String, String)] = []
        var log: [String] = []
        for key in c.allKeys.sorted(by: { $0.stringValue < $1.stringValue }) {
            if key.stringValue == "log", let entries = try? c.decode([String].self, forKey: key) {
                log = entries
            } else if let value = try? c.decode(Int.self, forKey: key) {
                lines.append((key.stringValue, String(value)))
            } else if let value = try? c.decode(Bool.self, forKey: key) {
                lines.append((key.stringValue, value ? "yes" : "no"))
            } else if let value = try? c.decode(String.self, forKey: key) {
                lines.append((key.stringValue, value))
            } else if let value = try? c.decode([String].self, forKey: key) {
                lines.append((key.stringValue, String(value.count)))
            }
        }
        self.lines = lines
        self.log = log
    }
}

// MARK: - Statistics

/// `{"2026-01": 12, "2026-02": "7"}` — the values may be strings.
public struct NumberMap: Codable, Sendable, Hashable {
    public var values: [String: Double]

    public init(values: [String: Double] = [:]) { self.values = values }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: any Decoder) throws {
        guard let c = try? decoder.container(keyedBy: AnyKey.self) else {
            values = [:]
            return
        }
        var values: [String: Double] = [:]
        for key in c.allKeys {
            if let value = try? c.decode(Double.self, forKey: key) {
                values[key.stringValue] = value
            } else if let value = try? c.decode(Bool.self, forKey: key) {
                values[key.stringValue] = value ? 1 : 0
            } else if let raw = try? c.decode(String.self, forKey: key), let value = Double(raw) {
                values[key.stringValue] = value
            }
        }
        self.values = values
    }

    public func encode(to encoder: any Encoder) throws {
        try values.encode(to: encoder)
    }

    public subscript(_ key: String) -> Double? { values[key] }

    /// Sorted by key, which for months is chronological.
    public var sorted: [(key: String, value: Double)] {
        values.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}

public struct NamedCount: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    @LenientInt public var count: Int
    public var id: String { name }

    public init(name: String, count: Int) {
        self.name = name
        _count = .init(wrappedValue: count)
    }
}

/// Somebody you trade replies with.
public struct ConversationPartner: Codable, Sendable, Hashable, Identifiable {
    public var account: String
    @LenientInt public var replies: Int
    public var id: String { account }

    public init(account: String, replies: Int) {
        self.account = account
        _replies = .init(wrappedValue: replies)
    }
}

/// `GET /api/v1/statistics`.
public struct AccountStatistics: Codable, Sendable, Hashable {
    public struct AccountSummary: Codable, Sendable, Hashable {
        public var acct: String
        @LenientInt public var followers: Int
        @LenientInt public var following: Int

        public init(acct: String, followers: Int, following: Int) {
            self.acct = acct
            _followers = .init(wrappedValue: followers)
            _following = .init(wrappedValue: following)
        }
    }

    public struct Window: Codable, Sendable, Hashable {
        @LenientInt public var days: Int
        @LenientInt public var counted: Int
        @LenientBool public var capped: Bool

        public init(days: Int, counted: Int, capped: Bool) {
            _days = .init(wrappedValue: days)
            _counted = .init(wrappedValue: counted)
            _capped = .init(wrappedValue: capped)
        }
    }

    public struct Activity: Codable, Sendable, Hashable {
        public var originals: NumberMap
        public var replies: NumberMap
        public var boosts: NumberMap

        public init(originals: NumberMap, replies: NumberMap, boosts: NumberMap) {
            self.originals = originals
            self.replies = replies
            self.boosts = boosts
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            originals = (try? c.decode(NumberMap.self, forKey: .originals)) ?? NumberMap()
            replies = (try? c.decode(NumberMap.self, forKey: .replies)) ?? NumberMap()
            boosts = (try? c.decode(NumberMap.self, forKey: .boosts)) ?? NumberMap()
        }
    }

    public struct Partners: Codable, Sendable, Hashable {
        public var inbound: [ConversationPartner]
        public var outbound: [ConversationPartner]

        public init(inbound: [ConversationPartner], outbound: [ConversationPartner]) {
            self.inbound = inbound
            self.outbound = outbound
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            inbound =
                (try? c.decode(LossyArray<ConversationPartner>.self, forKey: .inbound))?.elements
                ?? []
            outbound =
                (try? c.decode(LossyArray<ConversationPartner>.self, forKey: .outbound))?.elements
                ?? []
        }
    }

    public var account: AccountSummary?
    public var window: Window?
    public var posts: NumberMap
    public var engagement: NumberMap
    public var rates: NumberMap
    public var visibility: NumberMap
    public var consistency: NumberMap
    public var media: NumberMap
    public var byMonth: NumberMap
    public var engagementByMonth: NumberMap
    public var activity: Activity?
    public var partners: Partners?
    public var languages: [NamedCount]
    public var domains: [NamedCount]
    public var hashtags: [NamedCount]

    enum CodingKeys: String, CodingKey {
        case account, window, posts, engagement, rates, visibility, consistency, media
        case activity, partners, languages, domains, hashtags
        case byMonth = "by_month"
        case engagementByMonth = "engagement_by_month"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        account = try? c.decodeIfPresent(AccountSummary.self, forKey: .account)
        window = try? c.decodeIfPresent(Window.self, forKey: .window)
        posts = (try? c.decode(NumberMap.self, forKey: .posts)) ?? NumberMap()
        engagement = (try? c.decode(NumberMap.self, forKey: .engagement)) ?? NumberMap()
        rates = (try? c.decode(NumberMap.self, forKey: .rates)) ?? NumberMap()
        visibility = (try? c.decode(NumberMap.self, forKey: .visibility)) ?? NumberMap()
        consistency = (try? c.decode(NumberMap.self, forKey: .consistency)) ?? NumberMap()
        media = (try? c.decode(NumberMap.self, forKey: .media)) ?? NumberMap()
        byMonth = (try? c.decode(NumberMap.self, forKey: .byMonth)) ?? NumberMap()
        engagementByMonth =
            (try? c.decode(NumberMap.self, forKey: .engagementByMonth)) ?? NumberMap()
        activity = try? c.decodeIfPresent(Activity.self, forKey: .activity)
        partners = try? c.decodeIfPresent(Partners.self, forKey: .partners)
        languages = (try? c.decode(LossyArray<NamedCount>.self, forKey: .languages))?.elements ?? []
        domains = (try? c.decode(LossyArray<NamedCount>.self, forKey: .domains))?.elements ?? []
        hashtags = (try? c.decode(LossyArray<NamedCount>.self, forKey: .hashtags))?.elements ?? []
    }

    public init(
        account: AccountSummary? = nil, window: Window? = nil, posts: NumberMap = NumberMap(),
        engagement: NumberMap = NumberMap(), rates: NumberMap = NumberMap(),
        visibility: NumberMap = NumberMap(), consistency: NumberMap = NumberMap(),
        media: NumberMap = NumberMap(), byMonth: NumberMap = NumberMap(),
        engagementByMonth: NumberMap = NumberMap(), activity: Activity? = nil,
        partners: Partners? = nil, languages: [NamedCount] = [], domains: [NamedCount] = [],
        hashtags: [NamedCount] = []
    ) {
        self.account = account
        self.window = window
        self.posts = posts
        self.engagement = engagement
        self.rates = rates
        self.visibility = visibility
        self.consistency = consistency
        self.media = media
        self.byMonth = byMonth
        self.engagementByMonth = engagementByMonth
        self.activity = activity
        self.partners = partners
        self.languages = languages
        self.domains = domains
        self.hashtags = hashtags
    }
}

// MARK: - Channels

/// What a video belongs to everywhere but here: PeerTube's `Group`.
public struct VideoChannel: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var handle: String
    public var name: String
    public var description: String
    @LenientURL public var url: URL?
    @LenientInt public var videosCount: Int
    public var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, handle, name, description, url
        case videosCount = "videos_count"
        case createdAt = "created_at"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        handle = (try? c.decodeIfPresent(String.self, forKey: .handle)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
        _url = try c.decode(LenientURL.self, forKey: .url)
        _videosCount = try c.decode(LenientInt.self, forKey: .videosCount)
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    public init(
        id: String, handle: String, name: String, description: String = "", url: URL? = nil,
        videosCount: Int = 0, createdAt: Date? = nil
    ) {
        _id = .init(wrappedValue: id)
        self.handle = handle
        self.name = name
        self.description = description
        _url = .init(wrappedValue: url)
        _videosCount = .init(wrappedValue: videosCount)
        self.createdAt = createdAt
    }
}

/// Every channel route answers `{"channels": [...]}`.
public struct VideoChannelList: Codable, Sendable, Hashable {
    public var channels: [VideoChannel]

    public init(channels: [VideoChannel]) { self.channels = channels }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channels = (try? c.decode(LossyArray<VideoChannel>.self, forKey: .channels))?.elements ?? []
    }
}

/// The pieces of `verify_credentials` the `Account` entity does not carry.
public struct CredentialsExtras: Codable, Sendable, Hashable {
    @LenientBool public var indexable: Bool

    public init(indexable: Bool = false) { _indexable = .init(wrappedValue: indexable) }
}
