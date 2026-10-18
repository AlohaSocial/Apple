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
    /// What a swipe across a post does, from each edge — Mail's model, where
    /// the person decides rather than the app. `.none` turns an edge off.
    public var leadingSwipeAction: SwipeAction
    public var trailingSwipeAction: SwipeAction

    /// One action a swipe can perform on a post. Each is also a button under
    /// the post and an item in its menu, so no action is gesture-only
    /// (docs/12 §3, Switch Control).
    public enum SwipeAction: String, Codable, Sendable, Hashable, CaseIterable {
        case none, reply, favourite, boost, bookmark
    }

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
        leadingSwipeAction: SwipeAction = .reply,
        trailingSwipeAction: SwipeAction = .favourite,
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
        self.leadingSwipeAction = leadingSwipeAction
        self.trailingSwipeAction = trailingSwipeAction
        self.enabledModes = enabledModes
        self.localNotificationKinds = localNotificationKinds
        self.pollFrequency = pollFrequency
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.notificationDeliveryMode = notificationDeliveryMode
        self.digestTimes = digestTimes
    }

    /// Field by field, each one falling back to its default.
    ///
    /// The settings are one encoded blob, and a blob that fails to decode
    /// is replaced by `AccountSettings()` (`AccountRecord.settings`). The
    /// synthesised decoder fails on any missing key, so every field this
    /// type ever gained reset *all* of a person's settings on the update
    /// that added it. A key that is absent, or that holds a case this build
    /// does not know, now costs only that one setting.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AccountSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        self.init(
            defaultVisibility: value(.defaultVisibility, defaults.defaultVisibility),
            defaultLanguage: value(.defaultLanguage, defaults.defaultLanguage),
            defaultSensitive: value(.defaultSensitive, defaults.defaultSensitive),
            alwaysShowContentWarningField: value(
                .alwaysShowContentWarningField, defaults.alwaysShowContentWarningField),
            warnAboutMissingAltText: value(
                .warnAboutMissingAltText, defaults.warnAboutMissingAltText),
            appendThreadNumbering: value(.appendThreadNumbering, defaults.appendThreadNumbering),
            sensitiveMediaPolicy: value(.sensitiveMediaPolicy, defaults.sensitiveMediaPolicy),
            autoplayVideo: value(.autoplayVideo, defaults.autoplayVideo),
            loopShorts: value(.loopShorts, defaults.loopShorts),
            startMuted: value(.startMuted, defaults.startMuted),
            showBoosts: value(.showBoosts, defaults.showBoosts),
            showReplies: value(.showReplies, defaults.showReplies),
            restoreTimelinePosition: value(
                .restoreTimelinePosition, defaults.restoreTimelinePosition),
            showNewPostsPill: value(.showNewPostsPill, defaults.showNewPostsPill),
            showPopularityCounts: value(.showPopularityCounts, defaults.showPopularityCounts),
            leadingSwipeAction: value(.leadingSwipeAction, defaults.leadingSwipeAction),
            trailingSwipeAction: value(.trailingSwipeAction, defaults.trailingSwipeAction),
            enabledModes: value(.enabledModes, defaults.enabledModes),
            localNotificationKinds: value(
                .localNotificationKinds, defaults.localNotificationKinds),
            pollFrequency: value(.pollFrequency, defaults.pollFrequency),
            quietHoursStart: value(.quietHoursStart, defaults.quietHoursStart),
            quietHoursEnd: value(.quietHoursEnd, defaults.quietHoursEnd),
            notificationDeliveryMode: value(
                .notificationDeliveryMode, defaults.notificationDeliveryMode),
            digestTimes: value(.digestTimes, defaults.digestTimes))
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
        enabledModes.filter { $0.isOffered && capabilities.supports($0) }
    }
}
