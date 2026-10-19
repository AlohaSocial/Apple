// SPDX-License-Identifier: MIT

import Foundation

// Aloha Social's queued imports and account moves (`MigrationController`).
// A list import, a move here and following the people a Bluesky account
// follows are no longer answered when they finish: each is queued and answers
// `202 {"import": …}`, and `GET /api/v1/migration/imports` is where it gets to.

/// One queued import, as `ImportJob::jsonSerialize()` exports it.
public struct MigrationImport: Codable, Sendable, Hashable, Identifiable {
    public enum Status: String, Codable, Sendable, Hashable {
        case queued, running, done, failed
        case unknown

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }

        /// Still to report back; the list is polled while one is.
        public var isActive: Bool { self == .queued || self == .running }
    }

    /// What was imported. Kept as the server's word, because a server newer
    /// than the app may queue kinds it does not know yet.
    public enum Kind: Sendable, Hashable {
        case follows, blocks, mutes, lists, posts, bookmarks, domainBlocks
        case moveIn, blueskyFollows
        case other(String)

        public init(rawValue: String) {
            switch rawValue {
            case "follows": self = .follows
            case "blocks": self = .blocks
            case "mutes": self = .mutes
            case "lists": self = .lists
            case "posts": self = .posts
            case "bookmarks": self = .bookmarks
            case "domain_blocks": self = .domainBlocks
            case "move_in": self = .moveIn
            case "bluesky_follows": self = .blueskyFollows
            default: self = .other(rawValue)
            }
        }

        public var rawValue: String {
            switch self {
            case .follows: "follows"
            case .blocks: "blocks"
            case .mutes: "mutes"
            case .lists: "lists"
            case .posts: "posts"
            case .bookmarks: "bookmarks"
            case .domainBlocks: "domain_blocks"
            case .moveIn: "move_in"
            case .blueskyFollows: "bluesky_follows"
            case .other(let raw): raw
            }
        }
    }

    @FlexibleID public var id: String
    public var kind: Kind
    public var status: Status
    @LenientInt public var total: Int
    @LenientInt public var done: Int
    @LenientInt public var skipped: Int
    @LenientInt public var failed: Int
    /// What the run said when it finished — the per-kind counts the old
    /// synchronous answer carried.
    public var report: MigrationReport
    public var createdAt: Date?
    public var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, kind, status, total, done, skipped, failed, report
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        kind = Kind(rawValue: (try? c.decode(String.self, forKey: .kind)) ?? "")
        status = (try? c.decode(Status.self, forKey: .status)) ?? .unknown
        _total = (try? c.decode(LenientInt.self, forKey: .total)) ?? LenientInt(wrappedValue: 0)
        _done = (try? c.decode(LenientInt.self, forKey: .done)) ?? LenientInt(wrappedValue: 0)
        _skipped = (try? c.decode(LenientInt.self, forKey: .skipped)) ?? LenientInt(wrappedValue: 0)
        _failed = (try? c.decode(LenientInt.self, forKey: .failed)) ?? LenientInt(wrappedValue: 0)
        report = (try? c.decode(MigrationReport.self, forKey: .report)) ?? MigrationReport()
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind.rawValue, forKey: .kind)
        try c.encode(status.rawValue, forKey: .status)
        try c.encode(total, forKey: .total)
        try c.encode(done, forKey: .done)
        try c.encode(skipped, forKey: .skipped)
        try c.encode(failed, forKey: .failed)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    public init(
        id: String, kind: Kind, status: Status, total: Int = 0, done: Int = 0,
        skipped: Int = 0, failed: Int = 0, report: MigrationReport = MigrationReport(),
        createdAt: Date? = nil, updatedAt: Date? = nil
    ) {
        _id = .init(wrappedValue: id)
        self.kind = kind
        self.status = status
        _total = .init(wrappedValue: total)
        _done = .init(wrappedValue: done)
        _skipped = .init(wrappedValue: skipped)
        _failed = .init(wrappedValue: failed)
        self.report = report
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// How far it got, 0…1, or `nil` before the run has counted its entries.
    public var progress: Double? {
        guard total > 0 else { return nil }
        return min(1, Double(done + skipped + failed) / Double(total))
    }
}

/// `{"imports": […]}`, newest first.
public struct MigrationImportList: Decodable, Sendable, Hashable {
    public var imports: [MigrationImport]

    public init(imports: [MigrationImport]) { self.imports = imports }

    enum CodingKeys: String, CodingKey { case imports }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        imports =
            (try? c.decode(LossyArray<MigrationImport>.self, forKey: .imports))?.elements ?? []
    }
}

/// What a queued import answers: `202 {"import": …}`, and for following the
/// people a Bluesky account follows, the account that was found too.
public struct MigrationQueued: Decodable, Sendable, Hashable {
    public var job: MigrationImport?
    public var account: BlueskyFollowSource?

    enum CodingKeys: String, CodingKey {
        case job = "import"
        case account
    }

    public init(job: MigrationImport?, account: BlueskyFollowSource? = nil) {
        self.job = job
        self.account = account
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        job = try? c.decodeIfPresent(MigrationImport.self, forKey: .job)
        account = try? c.decodeIfPresent(BlueskyFollowSource.self, forKey: .account)
    }
}

/// The Bluesky account whose follows are being taken over
/// (`FollowFrom::resolve`).
public struct BlueskyFollowSource: Codable, Sendable, Hashable {
    public var did: String
    public var handle: String

    public init(did: String, handle: String) {
        self.did = did
        self.handle = handle
    }

    enum CodingKeys: String, CodingKey { case did, handle }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        did = (try? c.decode(String.self, forKey: .did)) ?? ""
        handle = (try? c.decode(String.self, forKey: .handle)) ?? ""
    }
}

/// Where this account stands on moving away (`MigrationService::moveStatus`).
public struct AccountMoveStatus: Codable, Sendable, Hashable {
    /// The account it moved to, by its ActivityPub id, or `nil`.
    public var movedTo: String?
    public var movedAt: Date?
    /// When the next move is allowed: thirty days after the last one.
    public var canMoveAt: Date?
    /// Where the move went, as the server confirms it after a move.
    public var target: Target?

    public struct Target: Codable, Sendable, Hashable {
        public var acct: String
        public var url: String

        public init(acct: String, url: String) {
            self.acct = acct
            self.url = url
        }
    }

    enum CodingKeys: String, CodingKey {
        case movedTo = "moved_to"
        case movedAt = "moved_at"
        case canMoveAt = "can_move_at"
        case target
    }

    public init(
        movedTo: String? = nil, movedAt: Date? = nil, canMoveAt: Date? = nil,
        target: Target? = nil
    ) {
        self.movedTo = movedTo
        self.movedAt = movedAt
        self.canMoveAt = canMoveAt
        self.target = target
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let moved = (try? c.decodeIfPresent(String.self, forKey: .movedTo)) ?? nil
        movedTo = (moved?.isEmpty ?? true) ? nil : moved
        // Unix seconds, and 0 for "never" — a date of 1970 would read as a
        // move long ago.
        movedAt = Self.timestamp(c, .movedAt)
        canMoveAt = Self.timestamp(c, .canMoveAt)
        target = try? c.decodeIfPresent(Target.self, forKey: .target)
    }

    private static func timestamp(
        _ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) -> Date? {
        guard let seconds = (try? c.decodeIfPresent(LenientInt.self, forKey: key))??.wrappedValue,
            seconds > 0
        else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    public var hasMoved: Bool { movedTo != nil }
}

/// The old account a move here starts from, as `move-in/inspect` reads it
/// off its own server — before anything happens.
public struct MoveInCandidate: Codable, Sendable, Hashable {
    public struct Collection: Codable, Sendable, Hashable {
        @LenientInt public var total: Int
        /// `false` when the old server answers a count and nothing more: the
        /// list is hidden on purpose, and the export file is the way instead.
        @LenientBool public var readable: Bool

        public init(total: Int, readable: Bool) {
            _total = .init(wrappedValue: total)
            _readable = .init(wrappedValue: readable)
        }
    }

    public var id: String
    public var acct: String
    public var name: String
    public var url: String
    @LenientURL public var avatar: URL?
    public var following: Collection
    public var posts: Collection
    /// The old server is Aloha Social too, so the last step — telling it to
    /// move — can be started from here.
    @LenientBool public var finishable: Bool

    enum CodingKeys: String, CodingKey {
        case id, acct, name, url, avatar, following, posts, finishable
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        acct = (try? c.decode(String.self, forKey: .acct)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? acct
        url = (try? c.decode(String.self, forKey: .url)) ?? id
        _avatar = (try? c.decode(LenientURL.self, forKey: .avatar)) ?? LenientURL(wrappedValue: nil)
        following =
            (try? c.decode(Collection.self, forKey: .following))
            ?? Collection(total: 0, readable: false)
        posts =
            (try? c.decode(Collection.self, forKey: .posts))
            ?? Collection(total: 0, readable: false)
        _finishable =
            (try? c.decode(LenientBool.self, forKey: .finishable))
            ?? LenientBool(wrappedValue: false)
    }

    public init(
        id: String, acct: String, name: String, url: String, avatar: URL? = nil,
        following: Collection, posts: Collection, finishable: Bool = false
    ) {
        self.id = id
        self.acct = acct
        self.name = name
        self.url = url
        _avatar = .init(wrappedValue: avatar)
        self.following = following
        self.posts = posts
        _finishable = .init(wrappedValue: finishable)
    }
}

/// `{"account": …}`, what `move-in/inspect` answers.
public struct MoveInInspection: Decodable, Sendable, Hashable {
    public var account: MoveInCandidate
}

/// Where a finish started from here stands (`MoveFinishService::status`).
public struct MoveInFinishStatus: Codable, Sendable, Hashable {
    public enum State: String, Codable, Sendable, Hashable {
        case none, pending, done, failed
        case unknown

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = State(rawValue: raw) ?? .unknown
        }
    }

    public var status: State
    public var acct: String
    public var error: String

    public init(status: State, acct: String = "", error: String = "") {
        self.status = status
        self.acct = acct
        self.error = error
    }

    enum CodingKeys: String, CodingKey { case status, acct, error }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = (try? c.decode(State.self, forKey: .status)) ?? .none
        acct = (try? c.decode(String.self, forKey: .acct)) ?? ""
        error = (try? c.decode(String.self, forKey: .error)) ?? ""
    }
}

/// `{"authorize_url": …}`: where to send the person to consent on the old
/// server.
public struct MoveInFinishStart: Decodable, Sendable, Hashable {
    @LenientURL public var authorizeURL: URL?

    enum CodingKeys: String, CodingKey { case authorizeURL = "authorize_url" }
}

/// What becomes of the account's Bluesky identity when it moves
/// (`BlueskyAfterMoveOut`): switched off unless the person says otherwise.
public enum BlueskyAfterMove: String, Sendable, Hashable, CaseIterable {
    case move, deactivate, keep
}
