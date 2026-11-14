// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// A tab on the phone's tab bar: a feed, or search.
///
/// Its own type rather than tagging the extra tab with a `FeedMode`, which
/// made them collide. Activities and Direct messages are toolbar buttons on
/// the feeds, not tabs: the system counts the search tab among the five, so
/// every feed and Search fit without "More".
enum ShellTab: Hashable, Codable, Sendable {
    case mode(FeedMode)
    case search

    /// Apple's ceiling for a phone's tab bar. A sixth tab becomes "More",
    /// which hides two tabs behind one to show one more.
    static let phoneTabLimit = 5

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
        case .profile: "aloha.tab.profile"
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
    /// What each row had open in the iPad's detail column. Optional so a
    /// restoration written before there was a detail column still reads.
    var detailPaths: [StoredSidebarItem: [Route]]?

    /// A deep stack is somebody who kept tapping, not a place to return to.
    /// The newest screens are the ones worth having back.
    static let maximumDepth = 12

    init(
        accountID: UUID, tab: ShellTab, tabPaths: [ShellTab: [Route]],
        sidebarItem: SidebarItem, sidebarPaths: [SidebarItem: [Route]],
        detailPaths: [SidebarItem: [Route]] = [:]
    ) {
        self.accountID = accountID
        self.tab = tab
        self.tabPaths = tabPaths.compactMapValues(Self.trimmed)
        self.sidebarItem = StoredSidebarItem(sidebarItem)
        self.sidebarPaths = Self.stored(sidebarPaths)
        let details = Self.stored(detailPaths)
        self.detailPaths = details.isEmpty ? nil : details
    }

    var restoredSidebarPaths: [SidebarItem: [Route]] {
        Self.restored(sidebarPaths)
    }

    var restoredDetailPaths: [SidebarItem: [Route]] {
        Self.restored(detailPaths ?? [:])
    }

    private static func stored(
        _ paths: [SidebarItem: [Route]]
    ) -> [StoredSidebarItem: [Route]] {
        Dictionary(
            paths.compactMap { item, path in
                trimmed(path).map { (StoredSidebarItem(item), $0) }
            },
            uniquingKeysWith: { _, last in last })
    }

    private static func restored(
        _ paths: [StoredSidebarItem: [Route]]
    ) -> [SidebarItem: [Route]] {
        Dictionary(paths.map { ($0.key.item, $0.value) }, uniquingKeysWith: { _, last in last })
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
