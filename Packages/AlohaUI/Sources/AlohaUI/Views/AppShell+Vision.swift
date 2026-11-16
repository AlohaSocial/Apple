// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

#if os(visionOS)
    /// The places that are tabs on visionOS, besides the feeds.
    enum VisionShell {
        /// Activities, messages, Discover and Search. Lists, albums,
        /// bookmarks and the rest of the account's places are in the account
        /// menu at the top of every tab: the tab bar is a column of symbols
        /// beside the window, and fourteen of them would be a ladder.
        static let tabRoutes: [Route] = [
            .notifications, .conversations, .explore, .search(query: nil),
        ]

        /// Whether `item` has a tab of its own in a shell showing `modes`.
        static func isTab(_ item: SidebarItem, modes: [FeedMode]) -> Bool {
            switch item {
            case .mode(let mode): modes.contains(mode)
            case .route(let route): tabRoutes.contains(route)
            }
        }
    }

    extension ThemedAppShell {
        /// The visionOS shell: a `TabView`, which visionOS draws as the
        /// column of tabs floating at the window's leading edge, with each
        /// tab's screen filling the window.
        ///
        /// It was the iPad's split view, whose sidebar took a quarter of the
        /// glass for a list of places and left the feed a column floating in
        /// the rest. The tab bar is visionOS's own navigation, and it puts
        /// the window's whole width to the posts.
        ///
        /// The selection is the same `sidebarItem` the other shells use, so
        /// links, notifications, Handoff and scene restoration all arrive
        /// the way they do everywhere else.
        func visionShell(_ session: AccountSession) -> some View {
            TabView(selection: $sidebarItem) {
                ForEach(session.visibleModes) { mode in
                    Tab(
                        modeTitle(mode), systemImage: mode.symbolName, value: SidebarItem.mode(mode)
                    ) {
                        visionTab(.mode(mode), session: session)
                    }
                }
                Tab(
                    "Activities", systemImage: AlohaSymbol.notifications,
                    value: SidebarItem.route(.notifications)
                ) {
                    visionTab(.route(.notifications), session: session)
                }
                .badge(unreadNotifications(session))
                Tab(
                    "Direct messages", systemImage: AlohaSymbol.directMessage,
                    value: SidebarItem.route(.conversations)
                ) {
                    visionTab(.route(.conversations), session: session)
                }
                .badge(unreadConversations)
                Tab("Discover", systemImage: "safari", value: SidebarItem.route(.explore)) {
                    visionTab(.route(.explore), session: session)
                }
                Tab(
                    "Search", systemImage: AlohaSymbol.search,
                    value: SidebarItem.route(.search(query: nil)), role: .search
                ) {
                    visionTab(.route(.search(query: nil)), session: session)
                }
            }
            .onChange(of: sidebarItem, initial: true) { _, item in
                if case .mode(let mode) = item { selectedMode = mode }
                keepOnATab(item, session: session)
            }
        }

        /// One tab's screen: its own stack, with the account menu and
        /// "New post" in its toolbar.
        private func visionTab(_ item: SidebarItem, session: AccountSession) -> some View {
            LazyShellContent(isSelected: sidebarItem == item) {
                NavigationStack(path: sidebarPath(item)) {
                    Group {
                        switch item {
                        case .mode(let mode): modeRoot(mode, session: session)
                        case .route(let route):
                            destination(route, session: session, isRoot: true)
                        }
                    }
                    .navigationDestination(for: Route.self) { destination($0, session: session) }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            AccountMenuButton(
                                session: session, onOpen: open,
                                onAddAccount: { presentSignIn() })
                        }
                        composeToolbar
                    }
                    .alohaWindowGround(palette)
                }
            }
        }

        /// A selection with no tab — a place restored from the Mac's
        /// sidebar, a feed since hidden — would leave the window empty, as
        /// a `TabView` shows nothing for a value none of its tabs has. The
        /// place is opened on the first feed's tab instead.
        private func keepOnATab(_ item: SidebarItem, session: AccountSession) {
            guard !VisionShell.isTab(item, modes: session.visibleModes) else { return }
            let feed = SidebarItem.mode(session.visibleModes.first ?? .home)
            let carried = sidebarPaths[item] ?? []
            sidebarItem = feed
            if case .route(let route) = item {
                sidebarPaths[feed, default: []] += [route] + carried
            }
        }
    }
#endif
