// SPDX-License-Identifier: MIT

import Foundation

/// Where a timeline's rows come from.
public enum TimelineSource: Codable, Sendable, Hashable {
    case home
    case local
    case federated
    case direct
    case favourites
    case bookmarks
    case list(id: String)
    case hashtag(name: String)
    case account(id: String, includeReplies: Bool, onlyMedia: Bool)
    case trending

    /// The `{timeline}` path segment, where this maps onto
    /// `/api/v1/timelines/{timeline}/`. `nil` for the ones with routes of their
    /// own — a list timeline is a name *and* an id, so it cannot be a name here.
    public var pathSegment: String? {
        switch self {
        case .home: "home"
        case .local, .federated: "public"
        case .direct: "direct"
        case .favourites: "favourites"
        case .bookmarks, .list, .hashtag, .account, .trending: nil
        }
    }

    /// `local=true` narrows `public` to this instance.
    public var isLocalOnly: Bool { self == .local }

    public var requiresViewer: Bool {
        switch self {
        case .federated, .local, .hashtag, .trending: false
        default: true
        }
    }

    public var storageKey: String {
        switch self {
        case .home: "home"
        case .local: "public:local"
        case .federated: "public:federated"
        case .direct: "direct"
        case .favourites: "favourites"
        case .bookmarks: "bookmarks"
        case .list(let id): "list:\(id)"
        case .hashtag(let name): "tag:\(name.lowercased())"
        case .account(let id, let replies, let media):
            "account:\(id):\(replies ? 1 : 0):\(media ? 1 : 0)"
        case .trending: "trending"
        }
    }
}

/// A mode plus a source. This is the cache key, and it is why Photos-of-home and
/// Home never share rows (docs/06 §1).
public struct TimelineKey: Codable, Sendable, Hashable {
    public var mode: FeedMode
    public var source: TimelineSource

    public init(mode: FeedMode, source: TimelineSource) {
        self.mode = mode
        self.source = source
    }

    public var storageKey: String { "\(mode.rawValue):\(source.storageKey)" }

    public static func home(_ source: TimelineSource = .home) -> TimelineKey {
        TimelineKey(mode: .home, source: source)
    }
}

/// The three narrowings Nextcloud Social accepts beyond Mastodon's parameters.
/// `only_video` is the narrower of the first two and wins when both are sent,
/// since every video is media (docs/02 §2).
public struct TimelineFilters: Sendable, Hashable {
    public var onlyMedia: Bool
    public var onlyVideo: Bool
    public var onlyNews: Bool

    public init(onlyMedia: Bool = false, onlyVideo: Bool = false, onlyNews: Bool = false) {
        self.onlyMedia = onlyMedia
        self.onlyVideo = onlyVideo
        self.onlyNews = onlyNews
    }

    public static let none = TimelineFilters()

    /// What to ask the server for, given the mode and what the server supports.
    /// A capability that is absent yields no parameter, and the caller then
    /// filters client-side with over-fetching.
    public static func forMode(
        _ mode: FeedMode, capabilities: ServerCapabilities
    ) -> TimelineFilters {
        switch mode {
        case .home:
            return .none
        case .photos:
            return TimelineFilters(onlyMedia: capabilities.onlyMediaFilter)
        case .video, .shorts:
            return capabilities.onlyVideoFilter
                ? TimelineFilters(onlyVideo: true)
                : TimelineFilters(onlyMedia: capabilities.onlyMediaFilter)
        case .news:
            return TimelineFilters(onlyNews: capabilities.onlyNewsFilter)
        case .audio:
            return TimelineFilters(onlyMedia: capabilities.onlyMediaFilter)
        }
    }

    public var isEmpty: Bool { !onlyMedia && !onlyVideo && !onlyNews }
}

/// How hard the client has to work to fill a page when the server cannot narrow
/// for it. Capped at 5 upstream pages per user-visible page (docs/06 §2).
public enum OverFetch {
    public static let maximumUpstreamPages = 5

    public static func multiplier(for mode: FeedMode, serverFilters: TimelineFilters) -> Int {
        guard serverFilters.isEmpty else { return 1 }
        switch mode {
        case .home: return 1
        case .photos: return 3
        case .video: return 5
        case .shorts: return 8
        case .news: return 1  // hidden entirely without server support
        case .audio: return 5
        }
    }
}
