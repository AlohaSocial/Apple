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
    /// no tab of its own — Direct messages, Discover, Settings — is pushed
    /// onto the feed's tab, above whatever was already on it, so the screen
    /// on show stays on show and Back still leads somewhere.
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
        case .notifications: .route(.notifications)
        }
    }

    private static func tab(for item: SidebarItem) -> ShellTab? {
        switch item {
        case .mode(let mode): .mode(mode)
        case .route(.notifications): .notifications
        case .route: nil
        }
    }
}
