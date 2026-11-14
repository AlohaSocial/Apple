// SPDX-License-Identifier: MIT

import AlohaModels
import SwiftUI

extension EnvironmentValues {
    /// Whether the shell on screen is the phone's tab bar, rather than the
    /// sidebar shell iPad, Mac, Vision and an unfolded iPhone Duo use. Read
    /// by the screens whose layout follows it — Shorts' column, the reading
    /// inset, where the audio player sits — so they follow the shell rather
    /// than the device: an iPhone Duo is a phone either way.
    @Entry var shellUsesTabBar = false
}

/// The two columns of the iPad shell in a wide window: the list a person is
/// reading, and the post or profile opened from it.
enum ShellColumn: Hashable {
    case primary
    case detail
}

/// Which shell a window shows, and how the place a person was in moves from
/// one shell to the other when that changes — an iPhone Duo folding or
/// unfolding.
enum ShellLayout {
    #if os(iOS)
        /// The sidebar shell on iPad, always: it adapts to a narrow window
        /// itself. On a phone only where the screen is regular both ways —
        /// an unfolded iPhone Duo — and not on a large iPhone turned
        /// sideways, which is regular wide but compact tall.
        static func usesSidebar(
            idiom: UIUserInterfaceIdiom,
            horizontal: UserInterfaceSizeClass?,
            vertical: UserInterfaceSizeClass?
        ) -> Bool {
            switch idiom {
            case .pad: true
            case .phone: horizontal == .regular && vertical == .regular
            default: false
            }
        }
    #endif

    // MARK: - The iPad's detail column

    /// The window width from which the iPad shell reads a post or a profile
    /// in a column beside the list it came from, rather than over it. Below
    /// it the primary column would be squeezed under a phone's width once a
    /// detail column and the sidebar take their share.
    nonisolated static let detailColumnMinimumWidth: CGFloat = 1100

    /// The detail column's width for a window this wide: enough for a
    /// thread at a readable measure, never so much that the list it was
    /// opened from becomes the narrow one.
    nonisolated static func detailColumnWidth(forWindowWidth width: CGFloat) -> CGFloat {
        min(max(width * 0.4, 420), 600)
    }

    /// What opens in the detail column when it is opened from the primary
    /// one: the things a list is a list *of*. Everything else — a hashtag, a
    /// list, a settings screen — is a place of its own and pushes as before.
    static func opensInDetailColumn(_ route: Route) -> Bool {
        switch route {
        case .thread, .profile, .handle: true
        default: false
        }
    }

    /// Where a route pushed from the primary column goes when the detail
    /// column can show: a post or a profile replaces whatever the column
    /// had open; anything else is pushed on the primary stack and leaves
    /// the column as it is. Without the column, everything is pushed — on
    /// top of what the column had open, which is where it is shown then.
    static func push(
        _ route: Route, primary: [Route], detail: [Route], showsDetailColumn: Bool
    ) -> (primary: [Route], detail: [Route]) {
        if showsDetailColumn {
            return opensInDetailColumn(route) ? (primary, [route]) : (primary + [route], detail)
        }
        return (primary + detail + [route], [])
    }

    /// Unfolding: each tab's stack becomes its sidebar row's.
    static func sidebarState(
        tab: ShellTab, tabPaths: [ShellTab: [Route]]
    ) -> (item: SidebarItem, paths: [SidebarItem: [Route]]) {
        var paths: [SidebarItem: [Route]] = [:]
        for (tab, path) in tabPaths {
            paths[sidebarItem(for: tab)] = path
        }
        return (sidebarItem(for: tab), paths)
    }

    /// Folding: each row that has a tab keeps its stack there. A place with
    /// no tab of its own — Activities, Direct messages, Discover, Settings —
    /// is pushed onto the feed's tab, above whatever was already on it, so
    /// the screen on show stays on show and Back still leads somewhere.
    static func tabState(
        item: SidebarItem, sidebarPaths: [SidebarItem: [Route]], feed: FeedMode
    ) -> (tab: ShellTab, paths: [ShellTab: [Route]]) {
        var paths: [ShellTab: [Route]] = [:]
        for (row, path) in sidebarPaths {
            if let tab = tab(for: row) { paths[tab] = path }
        }
        if let tab = tab(for: item) { return (tab, paths) }
        guard case .route(let route) = item else { return (.mode(feed), paths) }
        let feedTab = ShellTab.mode(feed)
        paths[feedTab, default: []] += [route] + (sidebarPaths[item] ?? [])
        return (feedTab, paths)
    }

    private static func sidebarItem(for tab: ShellTab) -> SidebarItem {
        switch tab {
        case .mode(let mode): .mode(mode)
        case .search: .route(.search(query: nil))
        }
    }

    private static func tab(for item: SidebarItem) -> ShellTab? {
        switch item {
        case .mode(let mode): .mode(mode)
        case .route(.search(query: nil)): .search
        case .route: nil
        }
    }
}
