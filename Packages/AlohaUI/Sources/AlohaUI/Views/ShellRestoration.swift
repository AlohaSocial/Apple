// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// A tab on the phone's tab bar: a feed, the messages, or the activities.
///
/// Its own type rather than tagging the extra tabs with a `FeedMode`, which
/// made them collide.
enum ShellTab: Hashable, Codable, Sendable {
    case mode(FeedMode)
    case messages
    case notifications

    /// Apple's ceiling for a phone's tab bar. A sixth tab becomes "More",
    /// which hides two tabs behind one to show one more.
    static let phoneTabLimit = 5

    /// Whether Activities earns a tab next to these feeds and Messages, or
    /// stays in the account menu (with a badge on it) because a tab would
    /// push the bar into "More".
    static func showsNotificationsTab(feedCount: Int) -> Bool {
        feedCount + 2 <= phoneTabLimit
    }

    /// The iPad tab customisation's name for a sidebar place. Stored by the
    /// system across launches, so these strings are a format: renaming one
    /// forgets where somebody had pinned it.
    static func customizationID(for route: Route) -> String {
        switch route {
        case .lists: "aloha.tab.lists"
        case .interests: "aloha.tab.interests"
        case .collections: "aloha.tab.albums"
        case .bookmarks: "aloha.tab.bookmarks"
        case .favourites: "aloha.tab.favourites"
        case .followRequests: "aloha.tab.followRequests"
        case .safety: "aloha.tab.blocking"
        case .archived: "aloha.tab.archived"
        case .statistics: "aloha.tab.statistics"
        case .settings: "aloha.tab.settings"
        case .notifications: "aloha.tab.notifications"
        case .conversations: "aloha.tab.conversations"
        case .explore: "aloha.tab.explore"
        default: "aloha.tab.other"
        }
    }
}

/// Where somebody was: the tab or sidebar row, and what they had pushed on
/// each. Kept per scene, so the app reopens on the thread it was showing
/// rather than on the top of the home feed (docs/05 §3).
///
/// Tied to the account it was written for: a thread pushed on one account
/// has no meaning on another, so a restoration for anybody else is ignored.
struct ShellRestoration: Codable, Hashable, Sendable {
    /// `SidebarItem` lives with the sidebar and is not `Codable`; this is the
    /// same choice in a shape that is.
    enum StoredSidebarItem: Codable, Hashable, Sendable {
        case mode(FeedMode)
        case route(Route)

        init(_ item: SidebarItem) {
            switch item {
            case .mode(let mode): self = .mode(mode)
            case .route(let route): self = .route(route)
            }
        }

        var item: SidebarItem {
            switch self {
            case .mode(let mode): .mode(mode)
            case .route(let route): .route(route)
            }
        }
    }

    var accountID: UUID
    var tab: ShellTab
    var tabPaths: [ShellTab: [Route]]
    var sidebarItem: StoredSidebarItem
    var sidebarPaths: [StoredSidebarItem: [Route]]

    /// A deep stack is somebody who kept tapping, not a place to return to.
    /// The newest screens are the ones worth having back.
    static let maximumDepth = 12

    init(
        accountID: UUID, tab: ShellTab, tabPaths: [ShellTab: [Route]],
        sidebarItem: SidebarItem, sidebarPaths: [SidebarItem: [Route]]
    ) {
        self.accountID = accountID
        self.tab = tab
        self.tabPaths = tabPaths.compactMapValues(Self.trimmed)
        self.sidebarItem = StoredSidebarItem(sidebarItem)
        self.sidebarPaths = Dictionary(
            sidebarPaths.compactMap { item, path in
                Self.trimmed(path).map { (StoredSidebarItem(item), $0) }
            },
            uniquingKeysWith: { _, last in last })
    }

    var restoredSidebarPaths: [SidebarItem: [Route]] {
        Dictionary(
            sidebarPaths.map { ($0.key.item, $0.value) }, uniquingKeysWith: { _, last in last })
    }

    private static func trimmed(_ path: [Route]) -> [Route]? {
        path.isEmpty ? nil : Array(path.suffix(maximumDepth))
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Nil for no data, data this build cannot read, or another account's.
    static func decode(_ data: Data?, for accountID: UUID) -> ShellRestoration? {
        guard let data,
            let restoration = try? JSONDecoder().decode(ShellRestoration.self, from: data),
            restoration.accountID == accountID
        else { return nil }
        return restoration
    }
}
