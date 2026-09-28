// SPDX-License-Identifier: MIT

import Foundation

/// `GET /api/v1/accounts/{id}/highlights` — Nextcloud Social's twelve-week
/// posting rhythm for a local account. Remote accounts answer
/// `available: false`, and the profile draws nothing.
public struct ProfileHighlights: Codable, Sendable, Hashable {
    @LenientBool public var available: Bool
    /// When the account was created.
    public var since: Date?
    /// One post count per week, oldest first; twelve entries when available.
    public var weeks: [Int]
    /// Featured hashtag names, when the server includes them here.
    public var hashtagNames: [String]

    enum CodingKeys: String, CodingKey {
        case available, since, weeks, hashtags
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _available =
            try c.decodeIfPresent(LenientBool.self, forKey: .available)
            ?? LenientBool(wrappedValue: false)
        if let seconds = try? c.decodeIfPresent(Double.self, forKey: .since), seconds > 0 {
            since = Date(timeIntervalSince1970: seconds)
        } else if let text = try? c.decodeIfPresent(String.self, forKey: .since),
            let seconds = Double(text), seconds > 0
        {
            since = Date(timeIntervalSince1970: seconds)
        } else {
            since = nil
        }
        weeks =
            (try? c.decodeIfPresent([LenientInt].self, forKey: .weeks))?
            .map(\.wrappedValue) ?? []
        // Either tag entities or bare names; both are just names here.
        if let tags = try? c.decodeIfPresent(LossyArray<FeaturedTag>.self, forKey: .hashtags) {
            hashtagNames = tags.elements.map(\.name)
        } else if let names = try? c.decodeIfPresent([String].self, forKey: .hashtags) {
            hashtagNames = names
        } else {
            hashtagNames = []
        }
    }

    public init(available: Bool, since: Date? = nil, weeks: [Int] = [], hashtagNames: [String] = [])
    {
        _available = .init(wrappedValue: available)
        self.since = since
        self.weeks = weeks
        self.hashtagNames = hashtagNames
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(available, forKey: .available)
        try c.encodeIfPresent(since.map { Int($0.timeIntervalSince1970) }, forKey: .since)
        try c.encode(weeks, forKey: .weeks)
        try c.encode(hashtagNames, forKey: .hashtags)
    }

    public var total: Int { weeks.reduce(0, +) }

    /// The one-line reading of the chart, so nobody has to read the chart.
    public enum Rhythm: Sendable, Hashable {
        case quiet, busier, slowing, steady
    }

    public var rhythm: Rhythm {
        guard weeks.count >= 4 else { return total == 0 ? .quiet : .steady }
        let recent = weeks.suffix(4).reduce(0, +)
        let earlier = weeks.dropLast(4).reduce(0, +)
        let earlierPerFour = Double(earlier) / Double(max(1, weeks.count - 4)) * 4
        if recent == 0 { return .quiet }
        if Double(recent) > earlierPerFour * 1.5 { return .busier }
        if Double(recent) < earlierPerFour * 0.5 { return .slowing }
        return .steady
    }
}

/// `GET /api/v1/accounts/familiar_followers` — for each asked account, the
/// people you follow who also follow it.
public struct FamiliarFollowers: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var accounts: [Account]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        accounts = (try? c.decode(LossyArray<Account>.self, forKey: .accounts))?.elements ?? []
    }

    public init(id: String, accounts: [Account]) {
        _id = .init(wrappedValue: id)
        self.accounts = accounts
    }

    enum CodingKeys: String, CodingKey {
        case id, accounts
    }
}

/// One person tagged in a photo (Pixelfed's `tagged_people`). The server
/// sends either an account-shaped object or a bare handle; both decode.
public struct TaggedPerson: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var acct: String
    public var displayName: String?

    public init(id: String, acct: String, displayName: String? = nil) {
        self.id = id
        self.acct = acct
        self.displayName = displayName
    }

    enum CodingKeys: String, CodingKey {
        case id, acct, username
        case displayName = "display_name"
    }

    public init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
            let handle = try? single.decode(String.self)
        {
            id = handle
            acct = handle
            displayName = nil
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let handle =
            (try? c.decodeIfPresent(String.self, forKey: .acct))
            ?? (try? c.decodeIfPresent(String.self, forKey: .username)) ?? ""
        id = (try? c.decodeIfPresent(FlexibleID.self, forKey: .id))?.wrappedValue ?? handle
        acct = handle
        displayName = try? c.decodeIfPresent(String.self, forKey: .displayName)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(acct, forKey: .acct)
        try c.encodeIfPresent(displayName, forKey: .displayName)
    }
}

/// `POST /api/v1.1/compose/tag` answers with the people now tagged.
public struct TaggedPeopleResponse: Codable, Sendable, Hashable {
    public var taggedPeople: [TaggedPerson]

    enum CodingKeys: String, CodingKey {
        case taggedPeople = "tagged_people"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taggedPeople =
            (try? c.decode(LossyArray<TaggedPerson>.self, forKey: .taggedPeople))?
            .elements ?? []
    }

    public init(taggedPeople: [TaggedPerson]) {
        self.taggedPeople = taggedPeople
    }
}

/// The `tagged_people` a status carries, read on its own so the status model
/// need not know about it.
public struct StatusTaggedPeople: Codable, Sendable, Hashable {
    public var taggedPeople: [TaggedPerson]

    enum CodingKeys: String, CodingKey {
        case taggedPeople = "tagged_people"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taggedPeople =
            (try? c.decode(LossyArray<TaggedPerson>.self, forKey: .taggedPeople))?
            .elements ?? []
    }

    public init(taggedPeople: [TaggedPerson]) {
        self.taggedPeople = taggedPeople
    }
}

/// Mastodon's list `replies_policy`.
public enum ListRepliesPolicy: String, CaseIterable, Sendable, Hashable {
    case followed, list, none
}
