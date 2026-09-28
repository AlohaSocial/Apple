// SPDX-License-Identifier: MIT

import Foundation

// MARK: - My interests

/// The reader's hashtag interests: what the server has learned, what it is
/// still weighing, and the switches that govern the learning.
///
/// Nextcloud Social only. Every field tolerates absence, since the shape has
/// grown by accretion on the server and a missing key must never empty the
/// screen.
public struct InterestsState: Decodable, Sendable, Hashable {
    public var settings: Settings
    public var interests: [InterestTag]
    public var candidates: [InterestTag]
    /// True when the server has too little to go on yet.
    @LenientBool public var thin: Bool

    public struct Settings: Decodable, Sendable, Hashable {
        @LenientBool public var learning: Bool
        @LenientBool public var paused: Bool
        public var languages: [String]

        public init(learning: Bool = true, paused: Bool = false, languages: [String] = []) {
            _learning = .init(wrappedValue: learning)
            _paused = .init(wrappedValue: paused)
            self.languages = languages
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            _learning =
                (try? c.decode(LenientBool.self, forKey: .learning)) ?? .init(wrappedValue: true)
            _paused =
                (try? c.decode(LenientBool.self, forKey: .paused)) ?? .init(wrappedValue: false)
            languages = (try? c.decode(LossyArray<String>.self, forKey: .languages))?.elements ?? []
        }

        enum CodingKeys: String, CodingKey { case learning, paused, languages }
    }

    public init(
        settings: Settings = Settings(), interests: [InterestTag] = [],
        candidates: [InterestTag] = [], thin: Bool = false
    ) {
        self.settings = settings
        self.interests = interests
        self.candidates = candidates
        _thin = .init(wrappedValue: thin)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = (try? c.decode(Settings.self, forKey: .settings)) ?? Settings()
        interests =
            (try? c.decode(LossyArray<InterestTag>.self, forKey: .interests))?.elements ?? []
        candidates =
            (try? c.decode(LossyArray<InterestTag>.self, forKey: .candidates))?.elements ?? []
        _thin = (try? c.decode(LenientBool.self, forKey: .thin)) ?? .init(wrappedValue: false)
    }

    enum CodingKeys: String, CodingKey { case settings, interests, candidates, thin }
}

/// One hashtag the server ranks, with how strongly.
public struct InterestTag: Decodable, Sendable, Hashable, Identifiable {
    public var tag: String
    public var score: Double
    @LenientBool public var pinned: Bool

    public var id: String { tag.lowercased() }

    public init(tag: String, score: Double = 0, pinned: Bool = false) {
        self.tag = tag
        self.score = score
        _pinned = .init(wrappedValue: pinned)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tag =
            try c.decodeIfPresent(String.self, forKey: .tag)
            ?? c.decodeIfPresent(String.self, forKey: .name) ?? ""
        if let value = try? c.decode(Double.self, forKey: .score) {
            score = value
        } else if let text = try? c.decode(String.self, forKey: .score), let value = Double(text) {
            score = value
        } else {
            score = 0
        }
        _pinned = (try? c.decode(LenientBool.self, forKey: .pinned)) ?? .init(wrappedValue: false)
    }

    enum CodingKeys: String, CodingKey { case tag, name, score, pinned }
}

// MARK: - Subscriptions

/// A feed outside the fediverse — RSS, Atom, a YouTube channel — that the
/// server reads on the viewer's behalf. Entries link out; nothing is copied.
public struct SubscriptionFeed: Decodable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    @LenientURL public var url: URL?
    public var title: String
    @LenientURL public var siteURL: URL?
    @LenientInt public var entryCount: Int
    /// The server's last word on reading the feed; `nil` when it read fine.
    public var error: String?
    public var lastReadAt: Date?

    public var displayTitle: String {
        if !title.isEmpty { return title }
        return siteURL?.host() ?? url?.host() ?? url?.absoluteString ?? id
    }

    public init(
        id: String, url: URL? = nil, title: String = "", siteURL: URL? = nil,
        entryCount: Int = 0, error: String? = nil, lastReadAt: Date? = nil
    ) {
        _id = .init(wrappedValue: id)
        _url = .init(wrappedValue: url)
        self.title = title
        _siteURL = .init(wrappedValue: siteURL)
        _entryCount = .init(wrappedValue: entryCount)
        self.error = error
        self.lastReadAt = lastReadAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        _url = (try? c.decode(LenientURL.self, forKey: .url)) ?? .init(wrappedValue: nil)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        _siteURL =
            (try? c.decode(LenientURL.self, forKey: .siteURL))
            ?? (try? c.decode(LenientURL.self, forKey: .link)) ?? .init(wrappedValue: nil)
        _entryCount =
            (try? c.decode(LenientInt.self, forKey: .entryCount))
            ?? (try? c.decode(LenientInt.self, forKey: .entries)) ?? .init(wrappedValue: 0)
        let raw = try? c.decodeIfPresent(String.self, forKey: .error)
        error = (raw?.isEmpty ?? true) ? nil : raw
        lastReadAt = try? c.decodeIfPresent(Date.self, forKey: .lastReadAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, url, title, link, error, entries
        case siteURL = "site_url"
        case entryCount = "entry_count"
        case lastReadAt = "last_read_at"
    }
}

/// One published entry from a subscribed feed.
public struct SubscriptionEntry: Decodable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var title: String
    @LenientURL public var url: URL?
    public var summary: String?
    public var publishedAt: Date?
    public var feedTitle: String?

    public init(
        id: String, title: String, url: URL? = nil, summary: String? = nil,
        publishedAt: Date? = nil, feedTitle: String? = nil
    ) {
        _id = .init(wrappedValue: id)
        self.title = title
        _url = .init(wrappedValue: url)
        self.summary = summary
        self.publishedAt = publishedAt
        self.feedTitle = feedTitle
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        _url =
            (try? c.decode(LenientURL.self, forKey: .url))
            ?? (try? c.decode(LenientURL.self, forKey: .link)) ?? .init(wrappedValue: nil)
        summary = try? c.decodeIfPresent(String.self, forKey: .summary)
        publishedAt =
            (try? c.decodeIfPresent(Date.self, forKey: .published))
            ?? (try? c.decodeIfPresent(Date.self, forKey: .publishedAt))
        feedTitle =
            (try? c.decodeIfPresent(String.self, forKey: .feedTitle))
            ?? (try? c.decodeIfPresent(String.self, forKey: .feed))
    }

    enum CodingKeys: String, CodingKey {
        case id, title, url, link, summary, published, feed
        case publishedAt = "published_at"
        case feedTitle = "feed_title"
    }
}

// MARK: - Memories

/// The weekly recap: how much you posted this week against last.
public struct WeeklyRecap: Decodable, Sendable, Hashable {
    @LenientBool public var enabled: Bool
    @LenientInt public var thisWeek: Int
    @LenientInt public var lastWeek: Int

    public init(enabled: Bool, thisWeek: Int = 0, lastWeek: Int = 0) {
        _enabled = .init(wrappedValue: enabled)
        _thisWeek = .init(wrappedValue: thisWeek)
        _lastWeek = .init(wrappedValue: lastWeek)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _enabled = (try? c.decode(LenientBool.self, forKey: .enabled)) ?? .init(wrappedValue: false)
        // Counts are omitted while the recap is off; zero is the honest reading.
        _thisWeek = (try? c.decode(LenientInt.self, forKey: .thisWeek)) ?? .init(wrappedValue: 0)
        _lastWeek = (try? c.decode(LenientInt.self, forKey: .lastWeek)) ?? .init(wrappedValue: 0)
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case thisWeek = "this_week"
        case lastWeek = "last_week"
    }
}

// MARK: - Held posts

/// One of your own posts a moderator has not yet looked at. Kept visible so
/// nothing somebody wrote goes missing without a word.
public struct HeldPost: Decodable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var createdAt: Date?
    public var spoilerText: String
    public var text: String
    @LenientInt public var mediaCount: Int
    public var reason: String?

    public init(
        id: String, createdAt: Date? = nil, spoilerText: String = "", text: String,
        mediaCount: Int = 0, reason: String? = nil
    ) {
        _id = .init(wrappedValue: id)
        self.createdAt = createdAt
        self.spoilerText = spoilerText
        self.text = text
        _mediaCount = .init(wrappedValue: mediaCount)
        self.reason = reason
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        spoilerText = (try? c.decodeIfPresent(String.self, forKey: .spoilerText)) ?? ""
        text =
            (try? c.decodeIfPresent(String.self, forKey: .text))
            ?? (try? c.decodeIfPresent(String.self, forKey: .content)) ?? ""
        _mediaCount =
            (try? c.decode(LenientInt.self, forKey: .mediaCount)) ?? .init(wrappedValue: 0)
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
    }

    enum CodingKeys: String, CodingKey {
        case id, text, content, reason
        case createdAt = "created_at"
        case spoilerText = "spoiler_text"
        case mediaCount = "media_count"
    }
}

/// `GET /api/v1/review`: the held posts and the reasons the server may give.
public struct HeldPostsPage: Decodable, Sendable, Hashable {
    public var held: [HeldPost]
    public var reasons: [String]

    public init(held: [HeldPost] = [], reasons: [String] = []) {
        self.held = held
        self.reasons = reasons
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        held = (try? c.decode(LossyArray<HeldPost>.self, forKey: .held))?.elements ?? []
        reasons = (try? c.decode(LossyArray<String>.self, forKey: .reasons))?.elements ?? []
    }

    enum CodingKeys: String, CodingKey { case held, reasons }
}

// MARK: - Announcements

/// An administrator's announcement, with the reactions Mastodon lets readers
/// leave on it. Richer than `Announcement`, which predates reactions here.
public struct ServerAnnouncement: Decodable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var content: String
    @LenientBool public var read: Bool
    @LenientBool public var allDay: Bool
    public var publishedAt: Date?
    public var endsAt: Date?
    public var reactions: [Reaction]

    public struct Reaction: Decodable, Sendable, Hashable, Identifiable {
        public var name: String
        @LenientInt public var count: Int
        @LenientBool public var me: Bool
        @LenientURL public var url: URL?

        public var id: String { name }

        public init(name: String, count: Int = 0, me: Bool = false, url: URL? = nil) {
            self.name = name
            _count = .init(wrappedValue: count)
            _me = .init(wrappedValue: me)
            _url = .init(wrappedValue: url)
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
            _count = (try? c.decode(LenientInt.self, forKey: .count)) ?? .init(wrappedValue: 0)
            _me = (try? c.decode(LenientBool.self, forKey: .me)) ?? .init(wrappedValue: false)
            _url = (try? c.decode(LenientURL.self, forKey: .url)) ?? .init(wrappedValue: nil)
        }

        enum CodingKeys: String, CodingKey { case name, count, me, url }
    }

    public init(
        id: String, content: String, read: Bool = false, allDay: Bool = false,
        publishedAt: Date? = nil, endsAt: Date? = nil, reactions: [Reaction] = []
    ) {
        _id = .init(wrappedValue: id)
        self.content = content
        _read = .init(wrappedValue: read)
        _allDay = .init(wrappedValue: allDay)
        self.publishedAt = publishedAt
        self.endsAt = endsAt
        self.reactions = reactions
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        content = (try? c.decodeIfPresent(String.self, forKey: .content)) ?? ""
        _read = (try? c.decode(LenientBool.self, forKey: .read)) ?? .init(wrappedValue: false)
        _allDay = (try? c.decode(LenientBool.self, forKey: .allDay)) ?? .init(wrappedValue: false)
        publishedAt = try? c.decodeIfPresent(Date.self, forKey: .publishedAt)
        endsAt = try? c.decodeIfPresent(Date.self, forKey: .endsAt)
        reactions = (try? c.decode(LossyArray<Reaction>.self, forKey: .reactions))?.elements ?? []
    }

    enum CodingKeys: String, CodingKey {
        case id, content, read, reactions
        case allDay = "all_day"
        case publishedAt = "published_at"
        case endsAt = "ends_at"
    }
}
