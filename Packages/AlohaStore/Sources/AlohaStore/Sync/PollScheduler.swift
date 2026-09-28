// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// The interval table from docs/08 §3, as a pure function so it can be tested
/// without waiting for any of it.
public struct PollScheduler: Sendable, Hashable {
    public enum Activity: Sendable, Hashable {
        case interacting
        case idleShort
        case idleLong
        case background
    }

    public var isActiveAccount: Bool
    public var activity: Activity
    public var isLowPowerMode: Bool
    public var isCellular: Bool
    public var wifiOnlySync: Bool
    public var frequency: AccountSettings.PollFrequency

    public init(
        isActiveAccount: Bool,
        activity: Activity,
        isLowPowerMode: Bool = false,
        isCellular: Bool = false,
        wifiOnlySync: Bool = false,
        frequency: AccountSettings.PollFrequency = .normal
    ) {
        self.isActiveAccount = isActiveAccount
        self.activity = activity
        self.isLowPowerMode = isLowPowerMode
        self.isCellular = isCellular
        self.wifiOnlySync = wifiOnlySync
        self.frequency = frequency
    }

    /// `nil` means "do not poll on a timer" — manual mode, or a background
    /// state where `BGAppRefreshTask` is the only thing that should wake.
    public var interval: TimeInterval? {
        guard frequency != .manual else { return nil }
        guard activity != .background else { return nil }

        let base: TimeInterval
        switch (activity, isActiveAccount) {
        case (.interacting, true): base = 30
        case (.interacting, false): base = 180
        case (.idleShort, true): base = 60
        case (.idleShort, false): base = 300
        case (.idleLong, true): base = 120
        case (.idleLong, false): base = 600
        case (.background, _): return nil
        }

        var interval = base * frequency.multiplier
        if isLowPowerMode { interval *= 2 }
        return interval
    }

    /// On cellular with Wi-Fi-only sync on, notifications still poll — the badge
    /// staying wrong is worse than the bytes.
    public var scope: Scope {
        if isCellular && wifiOnlySync { return .notificationsOnly }
        return .full
    }

    public enum Scope: Sendable, Hashable {
        case full
        case notificationsOnly
    }
}

/// What one tick asks for, in priority order, within a three-request budget.
public struct PollPlan: Sendable, Hashable {
    public var wantsUnreadCount: Bool
    public var wantsTimeline: Bool
    public var wantsNotifications: Bool

    public init(wantsUnreadCount: Bool, wantsTimeline: Bool, wantsNotifications: Bool) {
        self.wantsUnreadCount = wantsUnreadCount
        self.wantsTimeline = wantsTimeline
        self.wantsNotifications = wantsNotifications
    }

    /// - Parameters:
    ///   - timelineRecentlyVisible: the timeline is on screen, or was in the
    ///     last five minutes. Nothing else is polled; other timelines refresh
    ///     on appear.
    ///   - unreadCountChanged: what step one found. Notifications are only
    ///     fetched when the cheap call says something happened.
    public static func make(
        scope: PollScheduler.Scope,
        timelineRecentlyVisible: Bool,
        unreadCountChanged: Bool
    ) -> PollPlan {
        PollPlan(
            wantsUnreadCount: true,
            wantsTimeline: scope == .full && timelineRecentlyVisible,
            wantsNotifications: unreadCountChanged
        )
    }

    public var requestCount: Int {
        [wantsUnreadCount, wantsTimeline, wantsNotifications].filter { $0 }.count
    }
}

/// Quiet hours, as a window that may wrap midnight.
public struct QuietHours: Sendable, Hashable {
    public var startHour: Int?
    public var endHour: Int?

    public init(startHour: Int?, endHour: Int?) {
        self.startHour = startHour
        self.endHour = endHour
    }

    /// The badge still updates during quiet hours; only the alert is withheld.
    public func isQuiet(at date: Date, calendar: Calendar = .current) -> Bool {
        guard let startHour, let endHour, startHour != endHour else { return false }
        let hour = calendar.component(.hour, from: date)
        if startHour < endHour { return hour >= startHour && hour < endHour }
        return hour >= startHour || hour < endHour
    }
}
