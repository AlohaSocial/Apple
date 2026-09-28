// SPDX-License-Identifier: MIT

import Foundation

/// Pixelfed's stories, as Nextcloud Social serves them: one picture or video
/// that stops existing after a day. A story has no timeline row — it is not a
/// post — but it does federate, as an `Add` whose object is a `Story`.
public struct Story: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var account: Account
    @LenientURL public var url: URL?
    @LenientURL public var previewURL: URL?
    public var type: AttachmentKind
    public var caption: String?
    /// Clamped by the server to 3–30 seconds.
    public var duration: Double
    public var publishedAt: Date
    public var expiresAt: Date
    @LenientBool public var seen: Bool
    /// Filled in only on `/stories/carousel` and `/stories/self`: how many
    /// accounts watched is told to the poster and to nobody else.
    public var viewCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, account, url, type, caption, duration, seen, media
        case previewURL = "preview_url"
        case publishedAt = "published_at"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case viewCount = "view_count"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let partial = try PartialStory(from: decoder)
        account = try c.decode(Account.self, forKey: .account)
        _id = .init(wrappedValue: partial.id)
        _url = .init(wrappedValue: partial.url)
        _previewURL = .init(wrappedValue: partial.previewURL)
        type = partial.type
        caption = partial.caption
        duration = partial.duration
        publishedAt = partial.publishedAt
        expiresAt = partial.expiresAt
        _seen = .init(wrappedValue: partial.seen)
        viewCount = partial.viewCount
    }

    /// Written the flat way, which is what every route of this app's own
    /// server sends; the `media` and `created_at` keys exist only to read
    /// Pixelfed's shape.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(account, forKey: .account)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(previewURL, forKey: .previewURL)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(caption, forKey: .caption)
        try c.encode(duration, forKey: .duration)
        try c.encode(publishedAt, forKey: .publishedAt)
        try c.encode(expiresAt, forKey: .expiresAt)
        try c.encode(seen, forKey: .seen)
        try c.encodeIfPresent(viewCount, forKey: .viewCount)
    }

    public init(
        id: String, account: Account, url: URL? = nil, previewURL: URL? = nil,
        type: AttachmentKind = .image, caption: String? = nil, duration: Double = 5,
        publishedAt: Date = Date(), expiresAt: Date = Date().addingTimeInterval(86_400),
        seen: Bool = false, viewCount: Int? = nil
    ) {
        _id = .init(wrappedValue: id)
        self.account = account
        _url = .init(wrappedValue: url)
        _previewURL = .init(wrappedValue: previewURL)
        self.type = type
        self.caption = caption
        self.duration = duration
        self.publishedAt = publishedAt
        self.expiresAt = expiresAt
        _seen = .init(wrappedValue: seen)
        self.viewCount = viewCount
    }

    /// A story from a carousel node, where the account sits on the node and
    /// the story itself carries none.
    init(partial: PartialStory, account: Account, seen: Bool?) {
        self.init(
            id: partial.id, account: account, url: partial.url, previewURL: partial.previewURL,
            type: partial.type, caption: partial.caption, duration: partial.duration,
            publishedAt: partial.publishedAt, expiresAt: partial.expiresAt,
            seen: seen ?? partial.seen, viewCount: partial.viewCount)
    }

    /// Enforced client-side as well as by the server, and never longer than a
    /// day from insert whatever the sender claimed: for a feature whose promise
    /// is that the thing goes away, "what you can see" and "what is stored"
    /// have to be the same statement (docs/06 §6).
    public func isLive(at now: Date = Date(), insertedAt: Date? = nil) -> Bool {
        let hardCeiling = (insertedAt ?? publishedAt).addingTimeInterval(86_400)
        return now < min(expiresAt, hardCeiling)
    }
}

/// Everything about a story except who posted it. The Mastodon-shaped route
/// puts the account on the story; Pixelfed's v1.2 carousel puts it on the
/// node above a run of them. One decoder serves both.
struct PartialStory: Decodable, Sendable {
    var id: String
    var url: URL?
    var previewURL: URL?
    var type: AttachmentKind
    var caption: String?
    var duration: Double
    var publishedAt: Date
    var expiresAt: Date
    var seen: Bool
    var viewCount: Int?

    /// Pixelfed nests the file under `media`; Nextcloud Social flattens it.
    private struct Media: Decodable {
        @LenientURL var url: URL?
        @LenientURL var previewURL: URL?
        var type: AttachmentKind?
        enum CodingKeys: String, CodingKey {
            case url, type
            case previewURL = "preview_url"
        }
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Story.CodingKeys.self)
        id = try c.decode(FlexibleID.self, forKey: .id).wrappedValue
        let media = try? c.decodeIfPresent(Media.self, forKey: .media)
        url = (try? c.decode(LenientURL.self, forKey: .url))?.wrappedValue ?? media?.url
        previewURL =
            (try? c.decode(LenientURL.self, forKey: .previewURL))?.wrappedValue
            ?? media?.previewURL
        type = (try? c.decodeIfPresent(AttachmentKind.self, forKey: .type)) ?? media?.type ?? .image
        caption = try? c.decodeIfPresent(String.self, forKey: .caption)
        duration =
            (try? c.decodeIfPresent(Double.self, forKey: .duration))
            ?? (try? c.decodeIfPresent(String.self, forKey: .duration)).flatMap(Double.init) ?? 5
        publishedAt =
            (try? c.decodeIfPresent(Date.self, forKey: .publishedAt))
            ?? (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        expiresAt =
            (try? c.decodeIfPresent(Date.self, forKey: .expiresAt))
            ?? publishedAt.addingTimeInterval(86_400)
        seen = (try? c.decode(LenientBool.self, forKey: .seen))?.wrappedValue ?? false
        viewCount = try? c.decodeIfPresent(Int.self, forKey: .viewCount)
    }
}

/// The stories rail, whichever shape the server chose: a flat array of
/// stories, or Pixelfed's `{self, nodes}` with one node per account.
public struct StoryCarousel: Decodable, Sendable {
    /// The viewer's own, when the server separates them.
    public var own: [Story]
    /// Everybody else's, in the order the server ranked the accounts.
    public var others: [Story]

    public init(own: [Story] = [], others: [Story] = []) {
        self.own = own
        self.others = others
    }

    private enum CodingKeys: String, CodingKey {
        case own = "self"
        case nodes
    }

    private struct Node: Decodable {
        var account: Account?
        var stories: [PartialStory]?
        var seen: LenientBool?
        /// Pixelfed nests the run under `nodes` too, on some versions.
        var nodes: [PartialStory]?
    }

    public init(from decoder: any Decoder) throws {
        if let flat = try? decoder.singleValueContainer().decode(LossyArray<Story>.self) {
            own = []
            others = flat.elements
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        own = (try? c.decodeIfPresent(LossyArray<Story>.self, forKey: .own))?.elements ?? []
        let nodes = (try? c.decodeIfPresent(LossyArray<Node>.self, forKey: .nodes))?.elements ?? []
        others = nodes.flatMap { node -> [Story] in
            guard let account = node.account else { return [] }
            let run = node.stories ?? node.nodes ?? []
            return run.map { Story(partial: $0, account: account, seen: node.seen?.wrappedValue) }
        }
    }
}

/// One reaction or comment on a story, told only to the story's poster.
public struct StoryReaction: Decodable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var account: Account
    /// An emoji, for a reaction.
    public var reaction: String?
    /// Text, for a comment.
    public var comment: String?
    public var createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, account, reaction, emoji, comment, caption, text
        case createdAt = "created_at"
        case profile
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        account =
            try (try? c.decode(Account.self, forKey: .account))
            ?? c.decode(Account.self, forKey: .profile)
        reaction =
            (try? c.decodeIfPresent(String.self, forKey: .reaction))
            ?? (try? c.decodeIfPresent(String.self, forKey: .emoji))
        comment =
            (try? c.decodeIfPresent(String.self, forKey: .comment))
            ?? (try? c.decodeIfPresent(String.self, forKey: .caption))
            ?? (try? c.decodeIfPresent(String.self, forKey: .text))
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        let decodedID = (try? c.decode(FlexibleID.self, forKey: .id))?.wrappedValue
        let fallbackID = "\(account.id)-\(reaction ?? comment ?? "")"
        _id = .init(wrappedValue: decodedID ?? fallbackID)
    }

    public init(
        id: String, account: Account, reaction: String? = nil, comment: String? = nil,
        createdAt: Date? = nil
    ) {
        _id = .init(wrappedValue: id)
        self.account = account
        self.reaction = reaction
        self.comment = comment
        self.createdAt = createdAt
    }
}

/// `GET /api/v1/stories/{id}/reactions` answers `{reactions: […]}`.
public struct StoryReactionList: Decodable, Sendable {
    public var reactions: [StoryReaction]

    public init(from decoder: any Decoder) throws {
        if let flat = try? decoder.singleValueContainer().decode(LossyArray<StoryReaction>.self) {
            reactions = flat.elements
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reactions =
            (try? c.decodeIfPresent(LossyArray<StoryReaction>.self, forKey: .reactions))?
            .elements ?? []
    }

    private enum CodingKeys: String, CodingKey { case reactions }
}

/// One entry of `/api/v1/videos/continue`: where the reader got to in a video.
/// Never federated, never shown to anybody else, never counted into anything.
public struct ContinueWatchingItem: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var statusID: String
    public var position: Double
    public var duration: Double
    public var updatedAt: Date?
    public var status: Status?

    public var id: String { statusID }

    enum CodingKeys: String, CodingKey {
        case position, duration, status
        case statusID = "status_id"
        case updatedAt = "updated_at"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _statusID = try c.decode(FlexibleID.self, forKey: .statusID)
        position = try c.decodeIfPresent(Double.self, forKey: .position) ?? 0
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        status = try? c.decodeIfPresent(Status.self, forKey: .status)
    }

    public init(
        statusID: String, position: Double, duration: Double, updatedAt: Date? = nil,
        status: Status? = nil
    ) {
        _statusID = .init(wrappedValue: statusID)
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
        self.status = status
    }

    public var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }
}

public enum WatchPositionRules {
    /// Below this, nothing is reported: a row for a video somebody opened and
    /// closed is noise.
    public static let minimumReportableSeconds: Double = 10
    /// Past this the server forgets the position rather than bookmarking the
    /// credits, because a continue-watching row that offers back a finished
    /// video is one nobody presses twice. The client mirrors it.
    public static let completionFraction: Double = 0.95
    /// Reports are coalesced: never more than one in this many seconds.
    public static let minimumReportGap: Double = 5
    /// The server allows 600 reports a minute; this is well inside it.
    public static let reportInterval: Double = 10

    public static func shouldReport(position: Double, duration: Double) -> Bool {
        position >= minimumReportableSeconds && duration > 0
    }

    public static func isComplete(position: Double, duration: Double) -> Bool {
        duration > 0 && position / duration >= completionFraction
    }
}

/// A Pixelfed album. Read and write where the capability is present.
public struct Collection: Codable, Sendable, Hashable, Identifiable {
    @FlexibleID public var id: String
    public var title: String
    public var description: String?
    @LenientURL public var url: URL?
    @LenientInt public var postCount: Int
    @LenientURL public var thumbnail: URL?
    public var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, description, url, thumbnail
        case postCount = "post_count"
        case updatedAt = "updated_at"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _id = try c.decode(FlexibleID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description)
        _url = try c.decode(LenientURL.self, forKey: .url)
        _postCount = try c.decode(LenientInt.self, forKey: .postCount)
        _thumbnail = try c.decode(LenientURL.self, forKey: .thumbnail)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public init(
        id: String, title: String, description: String? = nil, url: URL? = nil,
        postCount: Int = 0, thumbnail: URL? = nil, updatedAt: Date? = nil
    ) {
        _id = .init(wrappedValue: id)
        self.title = title
        self.description = description
        _url = .init(wrappedValue: url)
        _postCount = .init(wrappedValue: postCount)
        _thumbnail = .init(wrappedValue: thumbnail)
        self.updatedAt = updatedAt
    }
}
