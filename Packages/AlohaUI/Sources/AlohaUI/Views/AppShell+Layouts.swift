// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The shells themselves: the phone's tab bar, the iPad's tabs and sidebar,
/// and the split view on iPad, Mac and Vision, with the feeds at their roots
/// and the toolbars they wear.
extension ThemedAppShell {
    // MARK: - iPhone

    #if os(iOS)
        func tabShell(_ session: AccountSession) -> some View {
            TabView(selection: $selectedTab) {
                ForEach(session.visibleModes) { mode in
                    Tab(value: TabSelection.mode(mode)) {
                        NavigationStack(path: tabPath(.mode(mode))) {
                            modeRoot(mode, session: session)
                                .navigationDestination(for: Route.self) {
                                    destination($0, session: session)
                                }
                        }
                    } label: {
                        // The filled spelling while selected, the outline
                        // otherwise — Apple's own apps switch weight rather
                        // than colour to say "this is the tab you are on".
                        Image(
                            systemName: selectedTab == .mode(mode)
                                ? mode.selectedSymbolName : mode.symbolName
                        )
                        Text(modeTitle(mode))
                    }
                }

                // Activities follows the feeds, as in Nextcloud Social's
                // sidebar. Direct messages are a toolbar button on the feeds
                // (`timelineChrome`), which keeps the bar at five tabs or
                // fewer with every feed switched on.
                Tab(value: TabSelection.notifications) {
                    NavigationStack(path: tabPath(.notifications)) {
                        NotificationsView(session: session) { handle($0, session: session) }
                            .navigationDestination(for: Route.self) {
                                destination($0, session: session)
                            }
                    }
                } label: {
                    Image(
                        systemName: selectedTab == .notifications
                            ? AlohaSymbol.notificationsFilled : AlohaSymbol.notifications
                    )
                    Text("Activities", comment: "Tab title")
                }
                // The count the app icon already wears, where it can be
                // acted on. Zero draws no badge.
                .badge(unreadNotifications(session))
            }
            .onChange(of: selectedTab) { _, tab in
                if case .mode(let mode) = tab { selectedMode = mode }
            }
            // Reading down a feed gives the screen to the posts; scrolling
            // back up, or reaching the top, brings the bar back.
            .tabBarMinimizeBehavior(.onScrollDown)
            // Composing lives in the toolbar, where the platform puts it. The
            // accessory is for what plays across tabs: audio started in the
            // Audio feed keeps its controls on every other tab, and the slot
            // is only there while something is playing.
            .tabViewBottomAccessory(isEnabled: AudioPlayerCoordinator.shared.nowPlaying != nil) {
                AudioMiniPlayer()
            }
        }
    #endif

    #if os(iOS)
        /// The iPad's tab bar and sidebar, as one customisable set.
        ///
        /// Activities is a tab of its own with its unread count — it used to
        /// be a collapsed row in "Account", which vanished entirely whenever
        /// the iPad showed the tab bar instead of the sidebar. The Library and
        /// Account places are no longer sidebar-only: they sit in the sidebar
        /// and stay out of the tab bar by default, and the tab bar's own edit
        /// mode lets a person pin the ones they use (`TabViewCustomization`,
        /// kept per device).
        ///
        /// No inspector for threads and profiles: every list in the app pushes
        /// a `Route` onto the stack it lives in, and an inspector would need a
        /// second, parallel notion of "what is selected" in each of them. The
        /// reading column already keeps a thread at a readable width.
        func iPadShell(_ session: AccountSession) -> some View {
            TabView(selection: $sidebarItem) {
                ForEach(session.visibleModes) { mode in
                    Tab(
                        modeTitle(mode), systemImage: mode.symbolName, value: SidebarItem.mode(mode)
                    ) {
                        iPadDestination(.mode(mode), session: session)
                    }
                    .customizationID("aloha.tab.mode.\(mode.rawValue)")
                }
                Tab(
                    "Activities", systemImage: AlohaSymbol.notifications,
                    value: SidebarItem.route(.notifications)
                ) {
                    iPadDestination(.route(.notifications), session: session)
                }
                .badge(unreadNotifications(session))
                .customizationID("aloha.tab.notifications")
                Tab(
                    "Direct messages", systemImage: "envelope",
                    value: SidebarItem.route(.conversations)
                ) {
                    iPadDestination(.route(.conversations), session: session)
                }
                .badge(unreadConversations)
                .customizationID("aloha.tab.conversations")
                Tab("Discover", systemImage: "safari", value: SidebarItem.route(.explore)) {
                    iPadDestination(.route(.explore), session: session)
                }
                .customizationID("aloha.tab.explore")
                TabSection("Library") {
                    sidebarTab(
                        "Your lists", symbol: "list.bullet.rectangle", route: .lists,
                        session: session)
                    if session.capabilities.collections {
                        sidebarTab(
                            "Albums", symbol: "rectangle.stack",
                            route: .collections(accountID: nil), session: session)
                    }
                }
                .customizationID("aloha.section.library")
                TabSection("Account") {
                    sidebarTab(
                        "Bookmarks", symbol: AlohaSymbol.bookmark, route: .bookmarks,
                        session: session)
                    sidebarTab(
                        "Liked posts", symbol: AlohaSymbol.favourite, route: .favourites,
                        session: session)
                    sidebarTab(
                        "Follow requests", symbol: "person.badge.clock", route: .followRequests,
                        session: session)
                    sidebarTab(
                        "Blocking", symbol: "hand.raised", route: .safety, session: session)
                    if session.capabilities.isNextcloudSocial {
                        sidebarTab(
                            "Archived posts", symbol: "archivebox", route: .archived,
                            session: session)
                        sidebarTab(
                            "Statistics", symbol: "chart.bar.xaxis", route: .statistics,
                            session: session)
                    }
                    sidebarTab(
                        "Settings", symbol: AlohaSymbol.settings, route: .settings,
                        session: session)
                }
                .customizationID("aloha.section.account")
                .defaultSectionExpansion(.collapsed)
                Tab(
                    "Search", systemImage: "magnifyingglass",
                    value: SidebarItem.route(.search(query: nil)), role: .search
                ) {
                    iPadDestination(.route(.search(query: nil)), session: session)
                }
                .customizationID("aloha.tab.search")
            }
            .tabViewStyle(.sidebarAdaptable)
            .tabViewCustomization($tabCustomization)
            .tabViewSidebarBottomBar {
                AccountMenuButton(
                    session: session, onOpen: open,
                    onAddAccount: { isPresentingSignIn = true },
                    showsBrowseDestinations: false, showsName: true, usesCompactMenu: true)
            }
            .onChange(of: sidebarItem) { _, item in
                if case .mode(let mode) = item { selectedMode = mode }
            }
        }

        /// A Library or Account place: in the sidebar, out of the tab bar
        /// until a person pins it there.
        private func sidebarTab(
            _ title: LocalizedStringKey, symbol: String, route: Route, session: AccountSession
        ) -> some TabContent<SidebarItem> {
            Tab(title, systemImage: symbol, value: SidebarItem.route(route)) {
                iPadDestination(.route(route), session: session)
            }
            .customizationID(ShellTab.customizationID(for: route))
            .defaultVisibility(.hidden, for: .tabBar)
        }

        private func iPadDestination(_ item: SidebarItem, session: AccountSession) -> some View {
            AnyView(
                NavigationStack(path: sidebarPath(item)) {
                    Group {
                        switch item {
                        case .mode(let mode): modeRoot(mode, session: session)
                        case .route(let route): destination(route, session: session, isRoot: true)
                        }
                    }
                    .navigationDestination(for: Route.self) { destination($0, session: session) }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        iPadAccountToolbar(session)
                        composeToolbar
                    }
                    .alohaWindowGround(palette)
                })
        }
    #endif

    #if os(iOS)
        /// The account menu at the top of a root screen. In compact width — a
        /// narrow Stage Manager window, Slide Over — there is no sidebar to
        /// hold Library and Account, so the menu carries all of them instead.
        @ToolbarContentBuilder
        private func iPadAccountToolbar(_ session: AccountSession) -> some ToolbarContent {
            let isCompact = horizontalSizeClass == .compact
            ToolbarItem(id: "account-menu", placement: .topBarLeading) {
                AccountMenuButton(
                    session: session, onOpen: open,
                    onAddAccount: { isPresentingSignIn = true },
                    showsBrowseDestinations: isCompact, usesCompactMenu: !isCompact)
            }
        }
    #endif

    // MARK: - iPad, Mac, Vision

    func splitShell(_ session: AccountSession) -> some View {
        NavigationSplitView {
            SidebarView(
                session: session,
                selection: $sidebarItem,
                selectedSource: $selectedSource,
                onAddAccount: { isPresentingSignIn = true },
                onSwitchAccount: { environment.setActiveAccount($0) }
            )
            .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 320)
        } detail: {
            NavigationStack(path: sidebarPath(sidebarItem)) {
                Group {
                    switch sidebarItem {
                    case .mode(let mode):
                        modeRoot(mode, session: session)
                    case .route(let route):
                        destination(route, session: session, isRoot: true)
                    }
                }
                // On the root; a pushed screen carries its own (`destination`).
                // Declared once each, rather than on the stack *and* on every
                // screen, which drew two "New post" buttons side by side.
                .toolbar { composeToolbar }
                .navigationDestination(for: Route.self) { destination($0, session: session) }
            }
            // A stack per sidebar row, as on iPad: each row keeps what was
            // pushed on it. A fresh stack for each row rather than one stack
            // whose path is swapped, which would animate as a pop and a push.
            .id(sidebarItem)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            // The window's own ground, not the system's. A reading column is
            // centred in this space, and without this the space around it was
            // window background — a cool white the app never uses — so the
            // column read as a sheet of paper dropped on the wrong desk.
            .alohaWindowGround(palette)
        }
        // A sidebar the width of its content, not the default narrow sliver:
        // "Direct messages" and "Waiting to be looked at" are two-line labels at the
        // default, and this is the navigation for a reading app on a big
        // screen.
        #if os(iOS)
            .navigationSplitViewStyle(.balanced)
        #elseif os(macOS)
            // The Mac's own convention: the content leads and the sidebar is
            // the affordance beside it. On iPad the balanced split is the one
            // Apple uses, and it is the default there.
            .navigationSplitViewStyle(.prominentDetail)
        #endif
        .onChange(of: sidebarItem) { _, item in
            if case .mode(let mode) = item { selectedMode = mode }
        }
    }

    @ToolbarContentBuilder
    var composeToolbar: some ToolbarContent {
        ToolbarItem(id: "compose-post", placement: composeToolbarPlacement) {
            Button {
                composing = ComposerPresentation()
            } label: {
                Label {
                    Text("New post", comment: "Toolbar action")
                } icon: {
                    Image(systemName: AlohaSymbol.compose)
                }
            }
            .keyboardShortcut("n", modifiers: .command)
            .help(Text("New post", comment: "Toolbar action"))
        }
    }

    private var composeToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
            .topBarTrailing
        #else
            .primaryAction
        #endif
    }

    @ViewBuilder
    private func modeRoot(_ mode: FeedMode, session: AccountSession) -> some View {
        switch mode {
        case .shorts:
            // Full screen, and there is no source to choose in it.
            ShortsView(session: session) { handle($0, session: session) }
                .navigationTitle(modeTitle(mode))
                #if os(iOS)
                    .toolbar(.hidden, for: .navigationBar)
                #endif

        case .photos:
            timelineChrome(
                PhotosModeView(session: session, source: selectedSource) {
                    handle($0, session: session)
                }
                .navigationTitle(modeTitle(mode)),
                session: session)

        case .video:
            timelineChrome(
                VideoModeView(session: session, source: selectedSource) {
                    handle($0, session: session)
                }
                .navigationTitle(modeTitle(mode)),
                session: session)

        case .audio:
            timelineChrome(
                AudioModeView(session: session, source: selectedSource) {
                    handle($0, session: session)
                }
                .navigationTitle(modeTitle(mode))
                // On a regular-width shell a timeline is a reading column:
                // full window width runs a post's text to 1,200pt, which is
                // unreadable. Mail and Reader constrain theirs; so does this.
                .readerColumn,
                session: session)

        case .news:
            timelineChrome(
                NewsModeView(session: session, source: selectedSource) {
                    handle($0, session: session)
                }
                .navigationTitle(modeTitle(mode))
                .readerColumn,
                session: session)

        case .home where selectedSource == .interests:
            // For you keeps its own list: each post says why it is there, and
            // "Show fewer like this" teaches the ranking.
            timelineChrome(
                InterestsView(session: session) { handle($0, session: session) }
                    .navigationTitle(sourceTitle)
                    #if !os(iOS)
                        .readerColumn
                    #endif
                , session: session)

        case .home:
            timelineChrome(
                TimelineView(
                    key: TimelineKey(mode: mode, source: selectedSource),
                    session: session
                ) { handle($0, session: session) }
                // The home mode is whichever of the three you are reading, so
                // the title says which rather than always "My Feed".
                .navigationTitle(sourceTitle)
                #if !os(iOS)
                    .readerColumn
                #endif
                .onAppear { environment.sync.noteTimelineVisible(for: session.id) },
                session: session)
        }
    }

    /// What every timeline screen wears: the account menu on a phone, and the
    /// source menu in its title.
    ///
    /// One modifier rather than a toolbar builder plus an inset at five call
    /// sites — and a `ToolbarContentBuilder` whose only item is iOS-only does
    /// not compile on a Mac.
    @ViewBuilder
    private func timelineChrome<Content: View>(
        _ content: Content, session: AccountSession
    ) -> some View {
        content
            // Identity, not just a new key. Every mode holds its model in
            // `@State`, which SwiftUI initialises once per view *identity* —
            // so switching source rebuilt the view with a new key and kept the
            // old model, and the timeline never changed. This is why the
            // source picker has never worked, in either of its forms.
            .id(selectedSource)
            .modifier(
                TimelineSourceMenu(
                    source: $selectedSource,
                    offersForYou: session.capabilities.isNextcloudSocial)
            )
            #if os(iOS)
                // The source menu is the title's, and only an inline title
                // carries one: as a large title — or inline-large — it drew no
                // chevron and tapping it opened nothing, so on a phone the
                // source could not be changed at all. iPad is inline already.
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    // Only on the phone: the split shell carries both of these
                    // in the sidebar — the account drawer at its foot, and a
                    // search field at its head.
                    if !usesSidebar {
                        ToolbarItem(placement: .topBarLeading) {
                            AccountMenuButton(
                                session: session,
                                onOpen: { open($0) },
                                onAddAccount: { isPresentingSignIn = true })
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink(value: Route.search(query: nil)) {
                                Image(systemName: AlohaSymbol.search)
                            }
                            .keyboardShortcut("f", modifiers: .command)
                            .accessibilityLabel(Text("Search", comment: "Toolbar button"))
                            .help(Text("Search", comment: "Toolbar button"))
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink(value: Route.conversations) {
                                Image(systemName: AlohaSymbol.envelope)
                            }
                            .badge(unreadConversations)
                            .accessibilityLabel(directMessagesLabel)
                            .help(Text("Direct messages", comment: "Toolbar button"))
                        }
                        // Finding and writing are different kinds of action;
                        // the gap keeps them in separate glass groups rather
                        // than one capsule that reads as a single control.
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                composing = ComposerPresentation()
                            } label: {
                                Image(systemName: AlohaSymbol.compose)
                            }
                            .keyboardShortcut("n", modifiers: .command)
                            .accessibilityLabel(Text("New post", comment: "Toolbar action"))
                            .help(Text("New post", comment: "Toolbar action"))
                        }
                    }
                }
            #endif
    }

    private var directMessagesLabel: Text {
        unreadConversations > 0
            ? Text(
                "Direct messages, \(unreadConversations) unread",
                comment: "Toolbar button with badge")
            : Text("Direct messages", comment: "Toolbar button")
    }
}
