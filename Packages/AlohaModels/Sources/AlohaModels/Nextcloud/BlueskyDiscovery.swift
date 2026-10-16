// SPDX-License-Identifier: MIT

import Foundation

// What Aloha Social reads off Bluesky to discover with: trending topics,
// suggested accounts and starter packs (`AtprotoFeedsController`,
// `BlueskyDiscovery`, `StarterPacks`). None of them are Mastodon entities —
// a suggested account is a handle and a DID, not an account this server holds —
// so they get their own small types rather than half-filled `Account`s.

/// One trending topic: a feed to read here, or a search to run.
public struct BlueskyTrend: Codable, Sendable, Hashable, Identifiable {
    public var topic: String
    public var label: String
    /// An `at://` feed URI when the topic has a feed of its own, else empty.
    public var feed: String
    /// What to search for when there is no feed.
    public var search: String

    public var id: String { topic + feed }

    public init(topic: String, label: String, feed: String = "", search: String = "") {
        self.topic = topic
        self.label = label
        self.feed = feed
        self.search = search
    }

    enum CodingKeys: String, CodingKey { case topic, label, feed, search }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        topic = (try? c.decode(String.self, forKey: .topic)) ?? ""
        label = (try? c.decode(String.self, forKey: .label)) ?? topic
        feed = (try? c.decode(String.self, forKey: .feed)) ?? ""
        search = (try? c.decode(String.self, forKey: .search)) ?? ""
    }

    public var title: String { label.isEmpty ? topic : label }
}

/// `{"trends": […]}`.
public struct BlueskyTrendList: Decodable, Sendable, Hashable {
    public var trends: [BlueskyTrend]

    enum CodingKeys: String, CodingKey { case trends }

    public init(trends: [BlueskyTrend]) { self.trends = trends }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trends = (try? c.decode(LossyArray<BlueskyTrend>.self, forKey: .trends))?.elements ?? []
    }
}

/// Somebody on Bluesky: a handle and a DID, with what Bluesky shows of them.
/// Following them goes through a lookup of the handle, which is how this
/// server learns about them.
public struct BlueskyPerson: Codable, Sendable, Hashable, Identifiable {
    public var did: String
    public var handle: String
    public var name: String
    @LenientURL public var avatar: URL?
    public var note: String
    /// Whether the reader follows them already; only starter-pack members
    /// say so.
    @LenientBool public var following: Bool

    public var id: String { did.isEmpty ? handle : did }
    public var displayName: String { name.isEmpty ? handle : name }

    enum CodingKeys: String, CodingKey {
        // Suggestions arrive in an account-like shape (`id`, `acct`,
        // `display_name`), starter-pack members in Bluesky's (`did`, `handle`,
        // `name`); both are read.
        case did, handle, name, avatar, description, following
        case id, acct, displayName = "display_name", note
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        did =
            (try? c.decode(String.self, forKey: .did))
            ?? (try? c.decode(String.self, forKey: .id)) ?? ""
        handle =
            (try? c.decode(String.self, forKey: .handle))
            ?? (try? c.decode(String.self, forKey: .acct)) ?? ""
        name =
            (try? c.decode(String.self, forKey: .name))
            ?? (try? c.decode(String.self, forKey: .displayName)) ?? ""
        _avatar = (try? c.decode(LenientURL.self, forKey: .avatar)) ?? LenientURL(wrappedValue: nil)
        // `note` is HTML-escaped by the server; `description` is plain.
        let escaped = (try? c.decode(String.self, forKey: .note)) ?? ""
        note = (try? c.decode(String.self, forKey: .description)) ?? Self.unescape(escaped)
        _following =
            (try? c.decode(LenientBool.self, forKey: .following))
            ?? LenientBool(wrappedValue: false)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(did, forKey: .did)
        try c.encode(handle, forKey: .handle)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(avatar, forKey: .avatar)
        try c.encode(note, forKey: .description)
        try c.encode(following, forKey: .following)
    }

    public init(
        did: String, handle: String, name: String = "", avatar: URL? = nil, note: String = "",
        following: Bool = false
    ) {
        self.did = did
        self.handle = handle
        self.name = name
        _avatar = .init(wrappedValue: avatar)
        self.note = note
        _following = .init(wrappedValue: following)
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

/// `{"accounts": […]}`, Bluesky's suggestions for the reader.
public struct BlueskySuggestionList: Decodable, Sendable, Hashable {
    public var accounts: [BlueskyPerson]

    enum CodingKeys: String, CodingKey { case accounts }

    public init(accounts: [BlueskyPerson]) { self.accounts = accounts }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts =
            (try? c.decode(LossyArray<BlueskyPerson>.self, forKey: .accounts))?.elements ?? []
    }
}

/// A Bluesky starter pack read by its address (`StarterPacks::read`).
public struct BlueskyStarterPack: Decodable, Sendable, Hashable, Identifiable {
    public var uri: String
    @LenientURL public var url: URL?
    public var name: String
    public var description: String
    @LenientInt public var joined: Int
    public var creator: BlueskyPerson?
    public var members: [BlueskyPerson]
    public var feeds: [BlueskyFeed]

    public var id: String { uri }

    enum CodingKeys: String, CodingKey {
        case uri, url, name, description, joined, creator, members, feeds
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uri = (try? c.decode(String.self, forKey: .uri)) ?? ""
        _url = (try? c.decode(LenientURL.self, forKey: .url)) ?? LenientURL(wrappedValue: nil)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        _joined = (try? c.decode(LenientInt.self, forKey: .joined)) ?? LenientInt(wrappedValue: 0)
        creator = try? c.decodeIfPresent(BlueskyPerson.self, forKey: .creator)
        members = (try? c.decode(LossyArray<BlueskyPerson>.self, forKey: .members))?.elements ?? []
        feeds = (try? c.decode(LossyArray<BlueskyFeed>.self, forKey: .feeds))?.elements ?? []
    }

    public init(
        uri: String, url: URL? = nil, name: String, description: String = "", joined: Int = 0,
        creator: BlueskyPerson? = nil, members: [BlueskyPerson] = [], feeds: [BlueskyFeed] = []
    ) {
        self.uri = uri
        _url = .init(wrappedValue: url)
        self.name = name
        self.description = description
        _joined = .init(wrappedValue: joined)
        self.creator = creator
        self.members = members
        self.feeds = feeds
    }
}

/// `{"pack": …}`.
public struct BlueskyStarterPackEnvelope: Decodable, Sendable, Hashable {
    public var pack: BlueskyStarterPack
}

/// What following a pack's members did: the DIDs followed, and those that
/// were not.
public struct BlueskyStarterPackFollowResult: Decodable, Sendable, Hashable {
    public var followed: [String]
    public var failed: [String]

    enum CodingKeys: String, CodingKey { case followed, failed }

    public init(followed: [String], failed: [String]) {
        self.followed = followed
        self.failed = failed
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        followed = (try? c.decode([String].self, forKey: .followed)) ?? []
        failed = (try? c.decode([String].self, forKey: .failed)) ?? []
    }
}
