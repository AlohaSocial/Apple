// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Where a route goes: which tab, sidebar row or stack the shell opens it on,
/// which of its two shells it shows, and the menu bar's way back.
extension ThemedAppShell {
    func open(_ route: Route) {
        // Mid-switch, the route is for the account arriving, not the one
        // still on screen; it is opened once the shell has reset for it.
        guard
            accountSwitch.shouldOpenNow(route, activeAccountID: environment.activeSession?.id)
        else { return }
        if case .timeline(let key) = route {
            selectedMode = key.mode
            selectedTab = .mode(key.mode)
            sidebarItem = .mode(key.mode)
            selectedSource = key.source
            tabPaths[.mode(key.mode)] = []
            sidebarPaths[.mode(key.mode)] = []
            detailPaths[.mode(key.mode)] = nil
        } else if !usesSidebar, route == .notifications {
            // Activities is a toolbar button on a phone's feeds: it opens on
            // the feed's own tab, once, however often it is asked for.
            if tabPaths[selectedTab]?.last != .notifications { push(.notifications) }
        } else if !usesSidebar, route == .search(query: nil) || route == .explore {
            // On a phone Search and Discover share the search tab.
            searchTabScope = route == .explore ? .discover : .search
            selectedTab = .search
            tabPaths[.search] = []
        } else if usesSidebar, rootRoutes.contains(route) {
            // On a split view these are sidebar rows, not pushes.
            sidebarItem = .route(route)
            sidebarPaths[.route(route)] = []
            detailPaths[.route(route)] = nil
        } else {
            push(route)
        }
    }

    private var rootRoutes: [Route] {
        #if os(iOS)
            return [
                .conversations, .explore, .lists,
                .collections(accountID: nil), .notifications, .bookmarks, .settings,
                .search(query: nil),
            ]
        #else
            return SidebarItem.sidebarRoutes
        #endif
    }

    /// The sidebar shell, or the phone's tab bar. By the screen rather than
    /// the device: an unfolded iPhone Duo is a phone with an iPad's room,
    /// and gets the iPad's shell (`ShellLayout`).
    var usesSidebar: Bool {
        #if os(iOS)
            ShellLayout.usesSidebar(
                idiom: UIDevice.current.userInterfaceIdiom,
                horizontal: horizontalSizeClass, vertical: verticalSizeClass)
        #else
            true
        #endif
    }

    /// Whether the iPad shell shows a detail column beside the primary one:
    /// a wide window, and not a window opened for one destination, which is
    /// already that destination's column of its own (`RouteWindow`).
    var showsDetailColumn: Bool {
        #if os(iOS)
            usesSidebar && isDetailColumnAvailable && initialRoute == nil
        #else
            false
        #endif
    }

    /// Folding or unfolding swaps the shell; the place a person was in
    /// moves across with it, so the screen they were reading stays.
    func handOver(toSidebar: Bool) {
        guard let session = environment.activeSession else { return }
        if !toSidebar {
            // A phone has no detail column: what it had open is pushed on
            // its row's stack first, as a narrow window shows it.
            for (item, detail) in detailPaths {
                sidebarPaths[item, default: []] += detail
            }
            detailPaths = [:]
        }
        if toSidebar {
            let state = ShellLayout.sidebarState(tab: selectedTab, tabPaths: tabPaths)
            sidebarItem = state.item
            sidebarPaths = state.paths
        } else {
            let feed =
                session.visibleModes.contains(selectedMode)
                ? selectedMode : session.visibleModes.first ?? .home
            let state = ShellLayout.tabState(
                item: sidebarItem, sidebarPaths: sidebarPaths, feed: feed)
            selectedTab = state.tab
            tabPaths = state.paths
        }
        repairFeedSelection(session.visibleModes)
    }

    // Erase at the platform boundary so the root does not embed every tab tree.
    func shell(_ session: AccountSession) -> AnyView {
        #if os(iOS)
            if usesSidebar {
                return AnyView(iPadShell(session))
            } else {
                return AnyView(tabShell(session))
            }
        #else
            return AnyView(splitShell(session))
        #endif
    }

    /// Onto the stack of whatever is showing: the current tab on a phone,
    /// the current sidebar row everywhere else.
    ///
    /// In a wide iPad window this is also where the detail column is
    /// decided, and the only place: every list hands its rows' actions to
    /// the shell, so a post or a profile opened from any of them lands in
    /// the column without the list knowing there is one. A screen inside
    /// the detail column was built by the shell's `.detail` copy, and what
    /// it opens stays in that column.
    func push(_ route: Route) {
        if usesSidebar {
            if column == .detail, showsDetailColumn {
                detailPaths[sidebarItem, default: []].append(route)
                return
            }
            let next = ShellLayout.push(
                route, primary: sidebarPaths[sidebarItem, default: []],
                detail: detailPaths[sidebarItem, default: []],
                showsDetailColumn: showsDetailColumn)
            sidebarPaths[sidebarItem] = next.primary
            detailPaths[sidebarItem] = next.detail.isEmpty ? nil : next.detail
        } else {
            tabPaths[selectedTab, default: []].append(route)
        }
    }

    /// Closes the detail column of the row on show.
    func closeDetailColumn(_ item: SidebarItem) {
        detailPaths[item] = nil
    }

    /// The menu bar's Back: one step off whichever stack is showing — the
    /// same one `push` adds to. With a detail column open, that is the
    /// column, and stepping back from its root closes it.
    private func goBack() {
        if showsDetailColumn, detailPaths[sidebarItem]?.isEmpty == false {
            detailPaths[sidebarItem]?.removeLast()
            if detailPaths[sidebarItem]?.isEmpty == true { detailPaths[sidebarItem] = nil }
        } else if usesSidebar {
            // The stack as shown, which in a narrow window includes what the
            // detail column had open (`sidebarPath`).
            let path = sidebarPath(sidebarItem)
            if !path.wrappedValue.isEmpty { path.wrappedValue.removeLast() }
        } else if tabPaths[selectedTab]?.isEmpty == false {
            tabPaths[selectedTab]?.removeLast()
        }
    }

    private var canGoBack: Bool {
        usesSidebar
            ? !sidebarPath(sidebarItem).wrappedValue.isEmpty
                || (showsDetailColumn && detailPaths[sidebarItem]?.isEmpty == false)
            : tabPaths[selectedTab]?.isEmpty == false
    }

    var shellCommands: ShellCommands? {
        guard let session = environment.activeSession else { return nil }
        return ShellCommands(
            compose: { composing = ComposerPresentation() },
            open: { open($0) },
            back: { goBack() },
            canGoBack: canGoBack,
            places: ShellPlace.sidebarOrder(modes: session.visibleModes, modeTitle: modeTitle))
    }
}
