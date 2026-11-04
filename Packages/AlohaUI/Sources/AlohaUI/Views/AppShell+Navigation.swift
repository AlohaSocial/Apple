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
        } else if !usesSidebar, route == .notifications {
            // On a phone activities are a tab, not a push.
            selectedTab = .notifications
            tabPaths[.notifications] = []
        } else if usesSidebar, rootRoutes.contains(route) {
            // On a split view these are sidebar rows, not pushes.
            sidebarItem = .route(route)
            sidebarPaths[.route(route)] = []
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

    /// Folding or unfolding swaps the shell; the place a person was in
    /// moves across with it, so the screen they were reading stays.
    func handOver(toSidebar: Bool) {
        guard let session = environment.activeSession else { return }
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
    func push(_ route: Route) {
        if usesSidebar {
            sidebarPaths[sidebarItem, default: []].append(route)
        } else {
            tabPaths[selectedTab, default: []].append(route)
        }
    }

    /// The menu bar's Back: one step off whichever stack is showing — the
    /// same one `push` adds to.
    private func goBack() {
        if usesSidebar {
            if sidebarPaths[sidebarItem]?.isEmpty == false {
                sidebarPaths[sidebarItem]?.removeLast()
            }
        } else if tabPaths[selectedTab]?.isEmpty == false {
            tabPaths[selectedTab]?.removeLast()
        }
    }

    private var canGoBack: Bool {
        usesSidebar
            ? sidebarPaths[sidebarItem]?.isEmpty == false
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
