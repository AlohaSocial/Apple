// SPDX-License-Identifier: MIT

import Foundation

// Aloha Social's own fields and settings, beyond Mastodon's entities. Every one
// is optional on the wire: a stock Mastodon sends none of them, and the server
// itself sends `null` wherever a field does not apply (docs/02 §2).

// MARK: - Who can reply

/// Who may reply to a post (`reply_policy`, an Aloha Social extension).
///
/// The server stores a comma-joined set (`Stream::setReplyRule`), so a wire
/// value can name several audiences. The composer offers one at a time, which
/// is what the web composer does too.
public enum ReplyPolicy: String, Codable, Sendable, Hashable, CaseIterable {
    case everyone
    case followers
    case following
    case mentioned
    case nobody

    /// The policy a wire value describes, or `nil` for one this app cannot
    /// draw. A set with more than one audience reads as its widest member,
    /// because that is who will actually be let in.
    public init?(wire: String?) {
        guard let wire, !wire.isEmpty else { return nil }
        let parts = wire.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        let order: [ReplyPolicy] = [.everyone, .followers, .following, .mentioned, .nobody]
        guard let widest = order.first(where: { parts.contains($0.rawValue) }) else {
            return nil
        }
        self = widest
    }
}

/// Where a reply stands with a server that approves replies.
public struct ReplyApproval: Codable, Sendable, Hashable {
    public var policy: String
    public var state: String

    public init(policy: String = "", state: String = "") {
        self.policy = policy
        self.state = state
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        policy = (try? c.decodeIfPresent(String.self, forKey: .policy)) ?? ""
        state = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? ""
    }

    enum CodingKeys: String, CodingKey { case policy, state }
}

// MARK: - For you

/// Why a post is on For you (`interest`, only on `/api/v1/timelines/interests`).
public struct StatusInterest: Codable, Sendable, Hashable {
    /// The hashtags that matched.
    public var tags: [String]
    /// `followed`, `interest`, `related` or `popular` — kept as the server's
    /// word, since a reason this app does not know is still worth a line.
    public var reason: String

    public init(tags: [String] = [], reason: String = "") {
        self.tags = tags
        self.reason = reason
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tags = (try? c.decode(LossyArray<String>.self, forKey: .tags))?.elements ?? []
        reason = (try? c.decodeIfPresent(String.self, forKey: .reason)) ?? ""
    }

    enum CodingKeys: String, CodingKey { case tags, reason }
}

/// One reading signal for For you (`POST /api/v1/interests/signals`).
///
/// The server reads each event as an object and skips anything else
/// (`InterestService::recordEvents`), so these go out as JSON, never as a form.
public struct InterestSignal: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case dwell, skip, open, media, link, mute
    }

    public enum Context: String, Codable, Sendable, Hashable {
        case home, local, federated, tag, explore, detail, interests, photos, videos, shorts
    }

    /// The post's id. The server only learns from its own (all digits), so
    /// anything else is never sent.
    public var statusID: String
    public var kind: Kind
    /// Time on screen. The server clamps to 30 s; so does this.
    public var milliseconds: Int
    public var context: Context

    public static let maximumMilliseconds = 30_000

    public init(statusID: String, kind: Kind, milliseconds: Int = 0, context: Context) {
        self.statusID = statusID
        self.kind = kind
        self.milliseconds = min(max(0, milliseconds), Self.maximumMilliseconds)
        self.context = context
    }

    /// Whether the server can learn anything from it at all.
    public var isLearnable: Bool {
        !statusID.isEmpty && statusID.allSatisfy(\.isASCIIDigit)
    }

    enum CodingKeys: String, CodingKey {
        case kind, context
        case statusID = "status_id"
        case milliseconds = "ms"
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

// MARK: - Bluesky

/// A post read from Bluesky (`Status.bluesky`): where it lives there, and the
/// labels on it with the labeler of each. `null` for every other post.
public struct BlueskyPostReference: Codable, Sendable, Hashable {
    public var uri: String
    @LenientURL public var url: URL?
    public var labels: [Label]

    public struct Label: Codable, Sendable, Hashable {
        public var source: String
        public var value: String

        public init(source: String, value: String) {
            self.source = source
            self.value = value
        }

        enum CodingKeys: String, CodingKey {
            case source = "src"
            case value = "val"
        }
    }

    public init(uri: String, url: URL? = nil, labels: [Label] = []) {
        self.uri = uri
        _url = .init(wrappedValue: url)
        self.labels = labels
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uri = (try? c.decodeIfPresent(String.self, forKey: .uri)) ?? ""
        _url = try c.decode(LenientURL.self, forKey: .url)
        labels = (try? c.decode(LossyArray<Label>.self, forKey: .labels))?.elements ?? []
    }

    enum CodingKeys: String, CodingKey { case uri, url, labels }
}

/// An account's Bluesky identity (`Account.bluesky`).
///
/// A native Bluesky account carries it on every export (`native: true`); a
/// local account only on `GET /api/v1/account/{username}/info`, which is where
/// the server attaches the handle it published for them (`native: false`).
public struct BlueskyAccountReference: Codable, Sendable, Hashable {
    public var handle: String
    public var did: String
    @LenientURL public var url: URL?
    @LenientBool public var native: Bool
    /// Bluesky's own verification of a native account.
    @LenientBool public var verified: Bool
    /// A local account's presence on Bluesky; `nil` on a native one.
    public var active: Bool?

    public init(
        handle: String, did: String = "", url: URL? = nil, native: Bool = false,
        verified: Bool = false, active: Bool? = nil
    ) {
        self.handle = handle
        self.did = did
        _url = .init(wrappedValue: url)
        _native = .init(wrappedValue: native)
        _verified = .init(wrappedValue: verified)
        self.active = active
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        handle = (try? c.decodeIfPresent(String.self, forKey: .handle)) ?? ""
        did = (try? c.decodeIfPresent(String.self, forKey: .did)) ?? ""
        _url = try c.decode(LenientURL.self, forKey: .url)
        _native = try c.decode(LenientBool.self, forKey: .native)
        _verified = try c.decode(LenientBool.self, forKey: .verified)
        active = (try? c.decodeIfPresent(LenientBool.self, forKey: .active))?.wrappedValue
    }

    /// `@alice.bsky.social`, the way Bluesky writes a handle.
    public var displayHandle: String { "@" + handle }

    /// A handle is shown only once there is one: the server hands out the
    /// identity before the handle resolves, and an empty "@" helps nobody.
    public var isShowable: Bool { !handle.isEmpty && active != false }

    enum CodingKeys: String, CodingKey { case handle, did, url, native, verified, active }
}

/// A feed or list the reader keeps on Bluesky
/// (`GET /api/v1/social/bluesky/feeds`).
public struct BlueskyFeed: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case feed, list
    }

    /// `at://…`, which is also what the timeline route takes.
    public var uri: String
    public var kind: Kind
    public var name: String
    public var description: String
    @LenientURL public var avatar: URL?
    /// The creator's handle.
    public var creator: String
    @LenientBool public var pinned: Bool

    public var id: String { uri }

    public init(
        uri: String, kind: Kind = .feed, name: String, description: String = "",
        avatar: URL? = nil, creator: String = "", pinned: Bool = false
    ) {
        self.uri = uri
        self.kind = kind
        self.name = name
        self.description = description
        _avatar = .init(wrappedValue: avatar)
        self.creator = creator
        _pinned = .init(wrappedValue: pinned)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uri = try c.decode(String.self, forKey: .uri)
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .feed
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
        _avatar = try c.decode(LenientURL.self, forKey: .avatar)
        creator = (try? c.decodeIfPresent(String.self, forKey: .creator)) ?? ""
        _pinned = try c.decode(LenientBool.self, forKey: .pinned)
    }

    /// What a row says when the feed has no name of its own.
    public var title: String { name.isEmpty ? uri : name }

    enum CodingKeys: String, CodingKey {
        case uri, name, description, avatar, creator, pinned
        case kind = "type"
    }
}

/// `{feeds: […]}`, the shape of both the kept and the suggested feeds.
public struct BlueskyFeedList: Decodable, Sendable, Hashable {
    public var feeds: [BlueskyFeed]

    public init(feeds: [BlueskyFeed]) { self.feeds = feeds }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        feeds = (try? c.decode(LossyArray<BlueskyFeed>.self, forKey: .feeds))?.elements ?? []
    }

    enum CodingKeys: String, CodingKey { case feeds }
}

/// `{feed: …}`, what keeping a feed answers.
public struct BlueskyFeedEnvelope: Decodable, Sendable, Hashable {
    public var feed: BlueskyFeed
}

/// The reader's own Bluesky identity (`GET /api/v1/social/bluesky/identity`).
public struct BlueskyIdentity: Codable, Sendable, Hashable {
    public var handle: String
    public var did: String
    @LenientURL public var url: URL?
    public var state: String
    /// `false` while the reader has switched their presence on Bluesky off.
    @LenientBool public var active: Bool
    /// Whether a recovery key has been made.
    @LenientBool public var recoveryKey: Bool
    public var assignedHandle: String
    public var customHandle: String
    @LenientBool public var customHandleBroken: Bool
    /// Whether blocks of Bluesky accounts are published there. `nil` when the
    /// answer did not say (the state route always does).
    public var publishBlocks: Bool?

    public init(
        handle: String, did: String = "", url: URL? = nil, state: String = "",
        active: Bool = true, recoveryKey: Bool = false, assignedHandle: String = "",
        customHandle: String = "", customHandleBroken: Bool = false, publishBlocks: Bool? = nil
    ) {
        self.handle = handle
        self.did = did
        _url = .init(wrappedValue: url)
        self.state = state
        _active = .init(wrappedValue: active)
        _recoveryKey = .init(wrappedValue: recoveryKey)
        self.assignedHandle = assignedHandle
        self.customHandle = customHandle
        _customHandleBroken = .init(wrappedValue: customHandleBroken)
        self.publishBlocks = publishBlocks
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        handle = (try? c.decodeIfPresent(String.self, forKey: .handle)) ?? ""
        did = (try? c.decodeIfPresent(String.self, forKey: .did)) ?? ""
        _url = try c.decode(LenientURL.self, forKey: .url)
        state = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? ""
        // An identity that does not say is one that is on: that is what the
        // server's own default is.
        active = (try? c.decodeIfPresent(LenientBool.self, forKey: .active))?.wrappedValue ?? true
        _recoveryKey = try c.decode(LenientBool.self, forKey: .recoveryKey)
        assignedHandle = (try? c.decodeIfPresent(String.self, forKey: .assignedHandle)) ?? ""
        customHandle = (try? c.decodeIfPresent(String.self, forKey: .customHandle)) ?? ""
        _customHandleBroken = try c.decode(LenientBool.self, forKey: .customHandleBroken)
        publishBlocks =
            (try? c.decodeIfPresent(LenientBool.self, forKey: .publishBlocks))?.wrappedValue
    }

    enum CodingKeys: String, CodingKey {
        case handle, did, url, state, active
        case recoveryKey = "recovery_key"
        case assignedHandle = "assigned_handle"
        case customHandle = "custom_handle"
        case customHandleBroken = "custom_handle_broken"
        case publishBlocks = "publish_blocks"
    }
}

/// `{publish_blocks: bool}`, what the publish-blocks switch answers.
public struct BlueskyPublishBlocks: Decodable, Sendable, Hashable {
    public var publishBlocks: Bool

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        publishBlocks = try c.decode(LenientBool.self, forKey: .publishBlocks).wrappedValue
    }

    enum CodingKeys: String, CodingKey { case publishBlocks = "publish_blocks" }
}

// MARK: - Profile extras

/// This instance's verification of an account (`Account.verification`).
public struct AccountVerification: Codable, Sendable, Hashable {
    /// Who it is in the name of — the instance's name.
    public var by: String
    /// The issuer's DID.
    public var issuer: String
    public var createdAt: Date?

    public init(by: String, issuer: String = "", createdAt: Date? = nil) {
        self.by = by
        self.issuer = issuer
        self.createdAt = createdAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        by = (try? c.decodeIfPresent(String.self, forKey: .by)) ?? ""
        issuer = (try? c.decodeIfPresent(String.self, forKey: .issuer)) ?? ""
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case by, issuer
        case createdAt = "created_at"
    }
}

// MARK: - Reader settings

/// `{hide: bool}`: the shape of both `/social/ai_content` and `/social/counts`.
public struct HideSetting: Codable, Sendable, Hashable {
    public var hide: Bool

    public init(hide: Bool) { self.hide = hide }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hide = try c.decode(LenientBool.self, forKey: .hide).wrappedValue
    }

    enum CodingKeys: String, CodingKey { case hide }
}

/// Who may start a direct conversation with the reader
/// (`/api/v1/social/direct_messages`).
public enum DirectMessageAudience: String, Codable, Sendable, Hashable, CaseIterable {
    case all, following, none
}

public struct DirectMessageSetting: Codable, Sendable, Hashable {
    public var from: DirectMessageAudience

    public init(from audience: DirectMessageAudience) { self.from = audience }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // An answer this app cannot read is the server's default.
        from = (try? c.decodeIfPresent(DirectMessageAudience.self, forKey: .from)) ?? .all
    }

    enum CodingKeys: String, CodingKey { case from }
}

/// How the server delivers the reader's Nextcloud notifications
/// (`/api/v1/social/notification_delivery`, `NotificationDelivery::toArray`).
public struct NotificationDeliverySettings: Codable, Sendable, Hashable {
    public enum Mode: String, Codable, Sendable, Hashable {
        case instant, digest
    }

    public var mode: Mode
    /// `"HH:MM"`, at most four.
    public var times: [String]
    public var passthroughDirect: Bool
    public var passthroughMentionsFromFollowed: Bool
    /// `"HH:MM"`, or `""` for no quiet hours.
    public var quietFrom: String
    public var quietTo: String

    public static let maximumTimes = 4

    public init(
        mode: Mode = .instant, times: [String] = [], passthroughDirect: Bool = true,
        passthroughMentionsFromFollowed: Bool = true, quietFrom: String = "", quietTo: String = ""
    ) {
        self.mode = mode
        self.times = Array(times.prefix(Self.maximumTimes))
        self.passthroughDirect = passthroughDirect
        self.passthroughMentionsFromFollowed = passthroughMentionsFromFollowed
        self.quietFrom = quietFrom
        self.quietTo = quietTo
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decodeIfPresent(Mode.self, forKey: .mode)) ?? .instant
        times = (try? c.decode(LossyArray<String>.self, forKey: .times))?.elements ?? []
        let pass = try? c.nestedContainer(keyedBy: PassKeys.self, forKey: .passthrough)
        passthroughDirect =
            (try? pass?.decode(LenientBool.self, forKey: .direct))?
            .wrappedValue ?? true
        passthroughMentionsFromFollowed =
            (try? pass?.decode(LenientBool.self, forKey: .mentionsFromFollowed))?.wrappedValue
            ?? true
        let quiet = try? c.nestedContainer(keyedBy: QuietKeys.self, forKey: .quiet)
        quietFrom = (try? quiet?.decodeIfPresent(String.self, forKey: .from)) ?? ""
        quietTo = (try? quiet?.decodeIfPresent(String.self, forKey: .to)) ?? ""
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(times, forKey: .times)
        var pass = c.nestedContainer(keyedBy: PassKeys.self, forKey: .passthrough)
        try pass.encode(passthroughDirect, forKey: .direct)
        try pass.encode(passthroughMentionsFromFollowed, forKey: .mentionsFromFollowed)
        var quiet = c.nestedContainer(keyedBy: QuietKeys.self, forKey: .quiet)
        try quiet.encode(quietFrom, forKey: .from)
        try quiet.encode(quietTo, forKey: .to)
    }

    /// `"HH:00"` for a whole hour — the only kind the app's own settings hold.
    public static func wireTime(hour: Int) -> String {
        let clamped = min(max(0, hour), 23)
        return clamped < 10 ? "0\(clamped):00" : "\(clamped):00"
    }

    /// The hour of a `"HH:MM"` value, or `nil` for `""` and anything malformed.
    public static func hour(of wire: String) -> Int? {
        let parts = wire.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), (0...23).contains(hour),
            let minute = Int(parts[1]), (0...59).contains(minute)
        else { return nil }
        return hour
    }

    enum CodingKeys: String, CodingKey { case mode, times, passthrough, quiet }
    enum PassKeys: String, CodingKey {
        case direct
        case mentionsFromFollowed = "mentions_from_followed"
    }
    enum QuietKeys: String, CodingKey { case from, to }
}

/// A shared mute or block list the reader subscribes to
/// (`/api/v1/social/moderation_lists`).
public struct ModerationList: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
        case mute, block
    }

    public var uri: String
    public var name: String
    public var kind: Kind
    /// How many accounts the list has muted or blocked so far.
    @LenientInt public var accounts: Int

    public var id: String { uri }

    public init(uri: String, name: String, kind: Kind, accounts: Int = 0) {
        self.uri = uri
        self.name = name
        self.kind = kind
        _accounts = .init(wrappedValue: accounts)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uri = try c.decode(String.self, forKey: .uri)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .mute
        _accounts = try c.decode(LenientInt.self, forKey: .accounts)
    }

    enum CodingKeys: String, CodingKey { case uri, name, kind, accounts }
}
