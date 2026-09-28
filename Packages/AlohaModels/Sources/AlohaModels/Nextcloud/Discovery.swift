// SPDX-License-Identifier: MIT

import Foundation

// Nextcloud Social's discovery surfaces: starter packs, other servers'
// directories, the follow graph, and Pixelfed's discover categories. All of
// them are optional and every decode here is lenient, because these are the
// routes most likely to change shape between server versions.

/// A curated bundle of accounts to follow in one go.
public struct StarterPack: Codable, Sendable, Hashable, Identifiable {
    public var slug: String
    public var name: String
    public var description: String
    /// The handles the pack names, before resolution.
    public var handles: [String]
    /// How many accounts the pack holds; the list route sends the number
    /// without resolving anybody.
    public var size: Int
    /// Resolved on the single-pack route only.
    public var accounts: [Account]

    public var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, name, description, handles, size, accounts
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decodeIfPresent(String.self, forKey: .slug) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? slug
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        handles = (try? c.decode([String].self, forKey: .handles)) ?? []
        accounts = (try? c.decode(LossyArray<Account>.self, forKey: .accounts))?.elements ?? []
        if let count = try? c.decode(LenientInt.self, forKey: .size).wrappedValue, count > 0 {
            size = count
        } else {
            size = max(handles.count, accounts.count)
        }
    }

    public init(
        slug: String, name: String, description: String = "", handles: [String] = [],
        size: Int? = nil, accounts: [Account] = []
    ) {
        self.slug = slug
        self.name = name
        self.description = description
        self.handles = handles
        self.accounts = accounts
        self.size = size ?? max(handles.count, accounts.count)
    }
}

/// One directory the server asks when searching beyond itself.
public struct DirectorySource: Codable, Sendable, Hashable, Identifiable {
    public var host: String
    public var kind: String
    public var label: String

    public var id: String { host }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? host
    }

    public init(host: String, kind: String = "", label: String? = nil) {
        self.host = host
        self.kind = kind
        self.label = label ?? host
    }

    enum CodingKeys: String, CodingKey { case host, kind, label }
}

/// What one source said when asked: how many it gave, or why nothing.
public struct DirectorySourceReport: Codable, Sendable, Hashable, Identifiable {
    public var host: String
    public var status: String?
    public var error: String?
    public var count: Int

    public var id: String { host }

    enum CodingKeys: String, CodingKey { case host, status, error, count, accounts, hashtags }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
        count =
            (try? c.decode(LenientInt.self, forKey: .count).wrappedValue)
            ?? (try? c.decode(LenientInt.self, forKey: .accounts).wrappedValue)
            ?? (try? c.decode(LenientInt.self, forKey: .hashtags).wrappedValue)
            ?? 0
    }

    public init(host: String, status: String? = nil, error: String? = nil, count: Int = 0) {
        self.host = host
        self.status = status
        self.error = error
        self.count = count
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(host, forKey: .host)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(error, forKey: .error)
        try c.encode(count, forKey: .count)
    }
}

/// `GET /api/v1/directories/search`: people found across the sources.
public struct DirectorySearchResults: Codable, Sendable, Hashable {
    public var accounts: [Account]
    public var sources: [DirectorySourceReport]

    enum CodingKeys: String, CodingKey { case accounts, sources }

    public init(from decoder: any Decoder) throws {
        // Either the documented object, or a bare array of accounts.
        if let c = try? decoder.container(keyedBy: CodingKeys.self) {
            accounts = (try? c.decode(LossyArray<Account>.self, forKey: .accounts))?.elements ?? []
            sources =
                (try? c.decode(LossyArray<DirectorySourceReport>.self, forKey: .sources))?
                .elements ?? []
        } else {
            accounts = (try? LossyArray<Account>(from: decoder))?.elements ?? []
            sources = []
        }
    }

    public init(accounts: [Account] = [], sources: [DirectorySourceReport] = []) {
        self.accounts = accounts
        self.sources = sources
    }
}

/// `GET /api/v1/directories/hashtags`: what other servers discuss.
public struct DirectoryHashtagResults: Codable, Sendable, Hashable {
    public var hashtags: [Tag]
    public var sources: [DirectorySourceReport]

    enum CodingKeys: String, CodingKey { case hashtags, tags, sources }

    public init(from decoder: any Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self) {
            hashtags =
                (try? c.decode(LossyArray<Tag>.self, forKey: .hashtags))?.elements
                ?? (try? c.decode(LossyArray<Tag>.self, forKey: .tags))?.elements ?? []
            sources =
                (try? c.decode(LossyArray<DirectorySourceReport>.self, forKey: .sources))?
                .elements ?? []
        } else {
            hashtags = (try? LossyArray<Tag>(from: decoder))?.elements ?? []
            sources = []
        }
    }

    public init(hashtags: [Tag] = [], sources: [DirectorySourceReport] = []) {
        self.hashtags = hashtags
        self.sources = sources
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hashtags, forKey: .hashtags)
        try c.encode(sources, forKey: .sources)
    }
}

/// Somebody the people you follow also follow, and how many of them do.
public struct FollowGraphSuggestion: Codable, Sendable, Hashable, Identifiable {
    public var account: Account
    /// How many of your follows follow this account.
    public var count: Int
    /// A few of the people who do, where the server names them.
    public var via: [Account]

    public var id: String { account.id }

    enum CodingKeys: String, CodingKey { case account, count, followers, via, through }

    public init(from decoder: any Decoder) throws {
        // Either `{account, count, via}` or a bare Account.
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
            let nested = try? c.decode(Account.self, forKey: .account)
        {
            account = nested
            count =
                (try? c.decode(LenientInt.self, forKey: .count).wrappedValue)
                ?? (try? c.decode(LenientInt.self, forKey: .followers).wrappedValue) ?? 0
            via =
                (try? c.decode(LossyArray<Account>.self, forKey: .via))?.elements
                ?? (try? c.decode(LossyArray<Account>.self, forKey: .through))?.elements ?? []
        } else {
            account = try Account(from: decoder)
            count = 0
            via = []
        }
    }

    public init(account: Account, count: Int = 0, via: [Account] = []) {
        self.account = account
        self.count = count
        self.via = via
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(account, forKey: .account)
        try c.encode(count, forKey: .count)
        try c.encode(via, forKey: .via)
    }
}

/// `GET /api/v1/follow_graph`.
public struct FollowGraph: Codable, Sendable, Hashable {
    public var suggestions: [FollowGraphSuggestion]
    /// How many of your follows the server asked.
    public var asked: Int
    /// How many follows a walk needs before it is worth anything.
    public var needs: Int

    enum CodingKeys: String, CodingKey { case suggestions, asked, needs }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        suggestions =
            (try? c.decode(LossyArray<FollowGraphSuggestion>.self, forKey: .suggestions))?
            .elements ?? []
        asked = (try? c.decode(LenientInt.self, forKey: .asked).wrappedValue) ?? 0
        needs = (try? c.decode(LenientInt.self, forKey: .needs).wrappedValue) ?? 0
    }

    public init(suggestions: [FollowGraphSuggestion] = [], asked: Int = 0, needs: Int = 0) {
        self.suggestions = suggestions
        self.asked = asked
        self.needs = needs
    }
}

/// `GET /api/v1/follow_graph/status`: whether a walk is worth the requests.
public struct FollowGraphStatus: Codable, Sendable, Hashable {
    public var isWorthwhile: Bool
    public var following: Int
    public var needs: Int

    enum CodingKeys: String, CodingKey { case worthwhile, eligible, ready, following, needs }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let flag =
            (try? c.decode(LenientBool.self, forKey: .worthwhile).wrappedValue)
            ?? (try? c.decode(LenientBool.self, forKey: .eligible).wrappedValue)
            ?? (try? c.decode(LenientBool.self, forKey: .ready).wrappedValue)
        following = (try? c.decode(LenientInt.self, forKey: .following).wrappedValue) ?? 0
        needs = (try? c.decode(LenientInt.self, forKey: .needs).wrappedValue) ?? 0
        // With no flag at all, enough follows is the answer.
        isWorthwhile = flag ?? (needs == 0 || following >= needs)
    }

    public init(isWorthwhile: Bool, following: Int = 0, needs: Int = 0) {
        self.isWorthwhile = isWorthwhile
        self.following = following
        self.needs = needs
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isWorthwhile, forKey: .worthwhile)
        try c.encode(following, forKey: .following)
        try c.encode(needs, forKey: .needs)
    }
}

/// A curated subject with the hashtags that make it up.
public struct DiscoverCategory: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var name: String
    public var hashtags: [String]

    enum CodingKeys: String, CodingKey { case id, name, hashtags, tags }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        let raw =
            (try? c.decode([String].self, forKey: .hashtags))
            ?? (try? c.decode([String].self, forKey: .tags)) ?? []
        hashtags = raw.compactMap(Tag.normalise)
        if let decoded = try? c.decode(FlexibleID.self, forKey: .id) {
            _id = decoded
        } else {
            _id = .init(wrappedValue: name.lowercased())
        }
    }

    public init(id: String, name: String, hashtags: [String]) {
        _id = .init(wrappedValue: id)
        self.name = name
        self.hashtags = hashtags
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(hashtags, forKey: .hashtags)
    }
}

/// `GET /api/v1.1/discover/categories`.
public struct DiscoverCategories: Codable, Sendable, Hashable {
    public var categories: [DiscoverCategory]

    enum CodingKeys: String, CodingKey { case categories }

    public init(from decoder: any Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self) {
            categories =
                (try? c.decode(LossyArray<DiscoverCategory>.self, forKey: .categories))?
                .elements ?? []
        } else {
            categories = (try? LossyArray<DiscoverCategory>(from: decoder))?.elements ?? []
        }
    }

    public init(categories: [DiscoverCategory]) {
        self.categories = categories
    }
}
