// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// Per-account preferences. Stored as an encoded blob on `AccountRecord`.
public struct AccountSettings: Codable, Sendable, Hashable {
    // Composing
    public var defaultVisibility: Visibility
    public var defaultLanguage: String?
    public var defaultSensitive: Bool
    public var alwaysShowContentWarningField: Bool
    public var warnAboutMissingAltText: Bool
    public var appendThreadNumbering: Bool

    // Reading
    public var sensitiveMediaPolicy: SensitiveMediaPolicy
    /// Autoplay is always on, on every network. One off-switch, no per-network
    /// middle state to reason about (docs/06 §4).
    public var autoplayVideo: Bool
    public var loopShorts: Bool
    public var startMuted: Bool
    public var showBoosts: Bool
    public var showReplies: Bool
    public var restoreTimelinePosition: Bool
    public var showNewPostsPill: Bool
    /// Show the popularity numbers on posts, profiles and media: reply,
    /// boost and favourite counts, follower and post counts, view and
    /// seen counts, and the "and N others" tail of a grouped notification.
    /// On by default, because a number is sometimes information — but
    /// comparing oneself is the most consistent harm social media does.
    public var showPopularityCounts: Bool

    // Modes
    public var enabledModes: [FeedMode]

    // Notifications
    public var localNotificationKinds: Set<String>
    public var pollFrequency: PollFrequency
    public var quietHoursStart: Int?
    public var quietHoursEnd: Int?
    /// How local notifications are delivered.
    public enum NotificationDeliveryMode: String, Codable, Sendable, Hashable, CaseIterable {
        /// Each notification is posted as it arrives (default, today's behaviour).
        case immediate
        /// Notifications are batched and delivered at the configured digest times.
        case digest
    }
    public var notificationDeliveryMode: NotificationDeliveryMode
    /// The times at which a digest is delivered (up to 4). Hours are in the
    /// user's local time zone; minutes are always zero. Empty array means
    /// the default single digest at 08:00.
    public var digestTimes: [Int]

    public enum PollFrequency: String, Codable, Sendable, Hashable, CaseIterable {
        case frequent, normal, batterySaver, manual

        /// Multiplier applied to the interval table in docs/08 §3.
        public var multiplier: Double {
            switch self {
            case .frequent: 0.5
            case .normal: 1
            case .batterySaver: 3
            case .manual: .infinity
            }
        }
    }

    public init(
        defaultVisibility: Visibility = .public,
        defaultLanguage: String? = nil,
        defaultSensitive: Bool = false,
        alwaysShowContentWarningField: Bool = false,
        warnAboutMissingAltText: Bool = true,
        appendThreadNumbering: Bool = false,
        sensitiveMediaPolicy: SensitiveMediaPolicy = .blur,
        autoplayVideo: Bool = true,
        loopShorts: Bool = true,
        startMuted: Bool = true,
        showBoosts: Bool = true,
        showReplies: Bool = true,
        restoreTimelinePosition: Bool = true,
        showNewPostsPill: Bool = true,
        showPopularityCounts: Bool = true,
        enabledModes: [FeedMode] = FeedMode.defaultEnabled,
        localNotificationKinds: Set<String> = Set(
            [
                NotificationKind.mention, .reblog, .favourite, .follow, .followRequest,
                .poll, .status, .update, .moderationWarning, .severedRelationships,
            ].map(\.rawValue)),
        pollFrequency: PollFrequency = .normal,
        quietHoursStart: Int? = nil,
        quietHoursEnd: Int? = nil,
        notificationDeliveryMode: NotificationDeliveryMode = .immediate,
        digestTimes: [Int] = [8]
    ) {
        self.defaultVisibility = defaultVisibility
        self.defaultLanguage = defaultLanguage
        self.defaultSensitive = defaultSensitive
        self.alwaysShowContentWarningField = alwaysShowContentWarningField
        self.warnAboutMissingAltText = warnAboutMissingAltText
        self.appendThreadNumbering = appendThreadNumbering
        self.sensitiveMediaPolicy = sensitiveMediaPolicy
        self.autoplayVideo = autoplayVideo
        self.loopShorts = loopShorts
        self.startMuted = startMuted
        self.showBoosts = showBoosts
        self.showReplies = showReplies
        self.restoreTimelinePosition = restoreTimelinePosition
        self.showNewPostsPill = showNewPostsPill
        self.showPopularityCounts = showPopularityCounts
        self.enabledModes = enabledModes
        self.localNotificationKinds = localNotificationKinds
        self.pollFrequency = pollFrequency
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.notificationDeliveryMode = notificationDeliveryMode
        self.digestTimes = digestTimes
    }

    /// Adopts what the server says this account's own defaults are. A client
    /// that cannot read these guesses, which is how it ends up posting publicly
    /// for somebody whose default is followers-only (docs/02 §2).
    public mutating func adopt(_ preferences: Preferences) {
        if let visibility = preferences.defaultVisibility, !visibility.isUnknown {
            defaultVisibility = visibility
        }
        defaultSensitive = preferences.defaultSensitive
        if let language = preferences.defaultLanguage { defaultLanguage = language }
        if let policy = preferences.expandMedia, !policy.isUnknown {
            sensitiveMediaPolicy = policy
        }
    }

    /// Which modes to show, filtered by what this server can actually source.
    public func visibleModes(capabilities: ServerCapabilities) -> [FeedMode] {
        enabledModes.filter { capabilities.supports($0) }
    }
}
