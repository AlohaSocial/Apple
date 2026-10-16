// SPDX-License-Identifier: MIT

import Foundation

public enum Visibility: String, UnknownPreserving {
    case `public`
    case unlisted
    case `private`
    case direct
    case unknownCase = "__unknown"

    public static func unknown(_ raw: String) -> Visibility { .unknownCase }
    public var isUnknown: Bool { self == .unknownCase }

    /// How restrictive this is, ascending. A reply can never be less
    /// restrictive than the post it answers (docs/07 §3).
    public var restrictiveness: Int {
        switch self {
        case .public: 0
        case .unlisted: 1
        case .private: 2
        case .direct: 3
        case .unknownCase: 3  // fail closed
        }
    }

    public static func mostRestrictive(_ lhs: Visibility, _ rhs: Visibility) -> Visibility {
        lhs.restrictiveness >= rhs.restrictiveness ? lhs : rhs
    }
}

public enum AttachmentKind: String, UnknownPreserving {
    case image
    case video
    case gifv
    case audio
    case unknown
    case unknownCase = "__unknown"

    public static func unknown(_ raw: String) -> AttachmentKind { .unknownCase }
    public var isUnknown: Bool { self == .unknownCase }

    public var isVisualMedia: Bool {
        self == .image || self == .video || self == .gifv
    }

    public var isPlayable: Bool {
        self == .video || self == .gifv || self == .audio
    }
}

/// The nine notification types Nextcloud Social serves, plus Mastodon's rest.
///
/// `admin.sign_up`, `admin.report` and `annual_report` are deliberately absent
/// there — they reach an administrator through Nextcloud's own notifications.
public enum NotificationKind: String, UnknownPreserving {
    case mention
    case reblog
    case favourite
    case follow
    case followRequest = "follow_request"
    case poll
    case status
    case update
    case moderationWarning = "moderation_warning"
    case severedRelationships = "severed_relationships"
    case adminSignUp = "admin.sign_up"
    case adminReport = "admin.report"
    case annualReport = "annual_report"

    // Aloha Social's own (`Stream::FIRST_PARTY_NOTIFICATION_TYPES`). The
    // server sends them to a client only when it names them in `types[]`.
    /// Somebody reacted to one of your stories.
    case storyReaction = "story:react"
    /// Somebody answered one of your stories.
    case storyComment = "story:comment"
    /// Somebody named you in a photograph.
    case tagged
    case blueskyRepostLiked = "bluesky:repost_liked"
    case blueskyRepostReposted = "bluesky:repost_reposted"
    case blueskyVerified = "bluesky:verified"
    case blueskyUnverified = "bluesky:unverified"
    case blueskyStarterPackJoined = "bluesky:starterpack_joined"
    case unknownCase = "__unknown"

    public static func unknown(_ raw: String) -> NotificationKind { .unknownCase }
    public var isUnknown: Bool { self == .unknownCase }

    /// Mentions never group — two people writing to you are two things to read.
    /// Nothing about a poll, an edit or a moderation decision groups either.
    public var groups: Bool {
        switch self {
        case .favourite, .reblog, .follow, .storyReaction, .blueskyRepostLiked,
            .blueskyRepostReposted:
            true
        default: false
        }
    }

    /// The types Mastodon's API defines that this app draws.
    public static let mastodonKinds: [NotificationKind] = [
        .mention, .status, .reblog, .follow, .followRequest, .favourite, .poll, .update,
        .adminSignUp, .adminReport, .severedRelationships, .moderationWarning, .annualReport,
    ]

    /// Aloha Social's own types, which a client has to ask for by name.
    public static let alohaKinds: [NotificationKind] = [
        .storyReaction, .storyComment, .tagged, .blueskyRepostLiked, .blueskyRepostReposted,
        .blueskyVerified, .blueskyUnverified, .blueskyStarterPackJoined,
    ]
}

public enum FilterAction: String, UnknownPreserving {
    case warn
    case hide
    case blur
    case unknownCase = "__unknown"

    public static func unknown(_ raw: String) -> FilterAction { .unknownCase }
    public var isUnknown: Bool { self == .unknownCase }
}

public enum FilterContext: String, UnknownPreserving {
    case home
    case notifications
    case `public`
    case thread
    case account
    case unknownCase = "__unknown"

    public static func unknown(_ raw: String) -> FilterContext { .unknownCase }
    public var isUnknown: Bool { self == .unknownCase }
}

/// PeerTube's three NSFW policies under the names Mastodon already has for the
/// same three states, which is exactly how Nextcloud Social serves
/// `reading:expand:media` (docs/02 §2).
public enum SensitiveMediaPolicy: String, UnknownPreserving {
    /// PeerTube's *display*: draw it.
    case showAll = "show_all"
    /// PeerTube's *blur*: covered, blurhash showing, one press away.
    case blur = "default"
    /// PeerTube's *hide*: not drawn, and no button to draw it — opening the
    /// post is what it takes.
    case hideAll = "hide_all"
    case unknownCase = "__unknown"

    public static func unknown(_ raw: String) -> SensitiveMediaPolicy { .unknownCase }
    public var isUnknown: Bool { self == .unknownCase }

    /// `''` is a fourth thing and not a fourth policy: it puts the account back
    /// to following the instance, which differs from choosing what the instance
    /// happens to do today.
    public static let followInstance = ""

    public var allowsAutomaticReveal: Bool { self == .showAll }
    public var drawsAtAll: Bool { self != .hideAll }
}
