// SPDX-License-Identifier: MIT

import Foundation

/// What one account's server can actually do.
///
/// Computed once at sign-in, refreshed on launch and every 24 h, persisted.
/// **Never inferred from a hostname**, and the governing rule (docs/02 §4) is
/// that a capability which cannot be determined is treated as absent — the app
/// must be fully usable with every flag false.
public struct ServerCapabilities: Codable, Sendable, Hashable {
    /// The resolved prefix Mastodon routes hang off. Not always the root.
    public var apiBase: URL
    /// From nodeinfo: `"nextcloud social"`, `"mastodon"`, …  Lowercased.
    public var softwareName: String
    public var softwareVersion: String
    public var mastodonAPIVersion: Int?

    // Transport
    public var streamingURL: URL?
    public var webPushVAPIDKey: String?

    // Mastodon 4.x surfaces
    public var groupedNotifications: Bool
    public var notificationPolicy: Bool
    public var filtersV2: Bool
    public var editHistory: Bool
    public var translation: Bool
    public var translationLanguages: [String: [String]]

    // Nextcloud Social extensions
    public var onlyMediaFilter: Bool
    public var onlyVideoFilter: Bool
    public var onlyNewsFilter: Bool
    public var hlsLadder: Bool
    public var watchPositions: Bool
    public var stories: Bool
    public var collections: Bool
    public var emojiReactions: Bool
    public var quotePosts: Bool
    public var mediaFromNextcloudFiles: Bool
    public var preferencesWrite: Bool

    public var limits: ServerLimits
    /// The colour this Nextcloud is wearing, read from its `theming`
    /// capability. `nil` on a plain Mastodon, and on a Nextcloud with the
    /// Theming app disabled.
    public var theme: NextcloudTheme?
    public var detectedAt: Date

    public init(
        apiBase: URL,
        softwareName: String = "",
        softwareVersion: String = "",
        mastodonAPIVersion: Int? = nil,
        streamingURL: URL? = nil,
        webPushVAPIDKey: String? = nil,
        groupedNotifications: Bool = false,
        notificationPolicy: Bool = false,
        filtersV2: Bool = false,
        editHistory: Bool = false,
        translation: Bool = false,
        translationLanguages: [String: [String]] = [:],
        onlyMediaFilter: Bool = false,
        onlyVideoFilter: Bool = false,
        onlyNewsFilter: Bool = false,
        hlsLadder: Bool = false,
        watchPositions: Bool = false,
        stories: Bool = false,
        collections: Bool = false,
        emojiReactions: Bool = false,
        quotePosts: Bool = false,
        mediaFromNextcloudFiles: Bool = false,
        preferencesWrite: Bool = false,
        limits: ServerLimits = .mastodonDefaults,
        theme: NextcloudTheme? = nil,
        detectedAt: Date = Date()
    ) {
        self.apiBase = apiBase
        self.softwareName = softwareName
        self.softwareVersion = softwareVersion
        self.mastodonAPIVersion = mastodonAPIVersion
        self.streamingURL = streamingURL
        self.webPushVAPIDKey = webPushVAPIDKey
        self.groupedNotifications = groupedNotifications
        self.notificationPolicy = notificationPolicy
        self.filtersV2 = filtersV2
        self.editHistory = editHistory
        self.translation = translation
        self.translationLanguages = translationLanguages
        self.onlyMediaFilter = onlyMediaFilter
        self.onlyVideoFilter = onlyVideoFilter
        self.onlyNewsFilter = onlyNewsFilter
        self.hlsLadder = hlsLadder
        self.watchPositions = watchPositions
        self.stories = stories
        self.collections = collections
        self.emojiReactions = emojiReactions
        self.quotePosts = quotePosts
        self.mediaFromNextcloudFiles = mediaFromNextcloudFiles
        self.preferencesWrite = preferencesWrite
        self.limits = limits
        self.theme = theme
        self.detectedAt = detectedAt
    }

    /// The most conservative thing that can be said about a server: it speaks
    /// the Mastodon API at this base and nothing else is known.
    public static func minimal(apiBase: URL) -> ServerCapabilities {
        ServerCapabilities(apiBase: apiBase)
    }
}

extension ServerCapabilities {
    /// Where the Nextcloud itself lives, as opposed to where its Mastodon API
    /// is served from.
    ///
    /// With the rewrite rules in place the two are the same host root; without
    /// them the API base is `…/index.php/apps/social/`, and the OCS routes —
    /// `theming` among them — are still at the root above it. Stripping the app
    /// prefix is the only way back up, since nothing announces the root.
    public var nextcloudRoot: URL {
        let text = apiBase.absoluteString
        guard let range = text.range(of: "index.php/apps/social/") else { return apiBase }
        return URL(string: String(text[text.startIndex..<range.lowerBound])) ?? apiBase
    }

    public var isNextcloudSocial: Bool {
        softwareName.contains("nextcloud") && softwareName.contains("social")
    }

    /// Which of the three sync tiers applies (docs/08 §2). They compose:
    /// streaming handles the foreground, polling still runs in the background
    /// where there is no Web Push.
    public var syncTier: SyncTier {
        if webPushVAPIDKey?.isEmpty == false { return .webPush }
        if streamingURL != nil { return .streaming }
        return .polling
    }

    public enum SyncTier: String, Codable, Sendable, Hashable {
        case webPush, streaming, polling
    }

    public func isStale(at now: Date = Date(), maximumAge: TimeInterval = 86_400) -> Bool {
        now.timeIntervalSince(detectedAt) > maximumAge
    }

    /// Whether a mode has anything to source from on this server. News has no
    /// client-side equivalent worth faking, so it is hidden rather than
    /// approximated (docs/06 §2).
    public func supports(_ mode: FeedMode) -> Bool {
        switch mode {
        case .home, .photos, .video, .shorts, .audio: true
        case .news: onlyNewsFilter
        }
    }
}
