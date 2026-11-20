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
                        // Titled: Photos, Videos and Shorts are all ways of
                        // looking at pictures, and their symbols alone left
                        // people guessing which tab was which.
                        Label {
                            Text(modeTitle(mode))
                        } icon: {
                            Image(
                                systemName: selectedTab == .mode(mode)
                                    ? mode.selectedSymbolName : mode.symbolName)
                        }
                    }
                }

                // Search, one tap from anywhere, where the system puts it.
                // It used to be a button on the feeds' toolbar, pushed over
                // whatever feed you were reading. Discover shares the tab —
                // finding people and finding posts are the same errand, and
                // Discover used to be buried in the account menu.
                //
                // The system counts the search tab among the five a phone's
                // bar holds before it turns the rest into "More", so the bar
                // is the feeds and Search. What comes *to* you — Activities
                // and Direct messages — sits at the top right of the feeds
                // (`timelineChrome`), each with its unread count.
                Tab(value: TabSelection.search, role: .search) {
                    NavigationStack(path: tabPath(.search)) {
                        searchTabRoot(session)
                            .navigationDestination(for: Route.self) {
                                destination($0, session: session)
                            }
                    }
                } label: {
                    Label {
                        Text("Search", comment: "Tab title")
                    } icon: {
                        Image(systemName: AlohaSymbol.search)
                    }
                }
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
        /// The phone's search tab: Search, or Discover beside it, chosen at
        /// the top. Both screens are hosted as they are; the tab only
        /// decides which one is showing (`searchTabScope`).
        private func searchTabRoot(_ session: AccountSession) -> some View {
            Group {
                switch searchTabScope {
                case .search: destination(.search(query: nil), session: session, isRoot: true)
                case .discover: destination(.explore, session: session, isRoot: true)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker(selection: $searchTabScope) {
                        Text("Search", comment: "Search tab scope").tag(SearchTabScope.search)
                        Text("Discover", comment: "Search tab scope").tag(SearchTabScope.discover)
                    } label: {
                        Text("Show", comment: "Search tab scope picker")
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        }
    #endif

    #if os(iOS)
        /// The iPad's tab bar and sidebar, as one customisable set.
        ///
        /// Activities is a tab of its own with its unread count — it used to
        /// be a collapsed row in "Account", which vanished entirely whenever
        /// the iPad showed the tab bar instead of the sidebar. The library and
        /// account places are no longer sidebar-only: they sit in the
        /// sidebar's "More" section, closed until opened, and stay out of the
        /// tab bar by default; the tab bar's own edit mode lets a person pin
        /// the ones they use (`TabViewCustomization`, kept per device).
        ///
        /// In a wide window a thread or a profile opens in a detail column
        /// beside the list it came from, rather than pushed over it, with a
        /// stack of its own so what is opened inside it stays there. Not an
        /// inspector with a selection in every list: every list in the app
        /// already hands its rows' actions to the shell, so the column is
        /// decided once, where routes are pushed (`push`), and no list knows
        /// it is there. A narrower window shows the same stack pushed, as
        /// before (`sidebarPath`).
        func iPadShell(_ session: AccountSession) -> some View {
            TabView(selection: $sidebarItem) {
                ForEach(session.visibleModes) { mode in
                    Tab(
                        modeTitle(mode), systemImage: mode.symbolName, value: SidebarItem.mode(mode)
                    ) {
                        // The TabView builds every tab's content at launch;
                        // each screen here is a NavigationStack with the whole
                        // destination switch in it. Building all of them at
                        // once overflowed the main thread's stack on a real
                        // iPad, so a tab's screen is built when it is first
                        // selected and kept afterwards.
                        LazyShellContent(isSelected: sidebarItem == .mode(mode)) {
                            iPadDestination(.mode(mode), session: session)
                        }
                    }
                    .customizationID("aloha.tab.mode.\(mode.rawValue)")
                }
                Tab(
                    "Activities", systemImage: AlohaSymbol.notifications,
                    value: SidebarItem.route(.notifications)
                ) {
                    LazyShellContent(isSelected: sidebarItem == .route(.notifications)) {
                        iPadDestination(.route(.notifications), session: session)
                    }
                }
                .badge(unreadNotifications(session))
                .customizationID("aloha.tab.notifications")
                Tab(
                    "Direct messages", systemImage: AlohaSymbol.directMessage,
                    value: SidebarItem.route(.conversations)
                ) {
                    LazyShellContent(isSelected: sidebarItem == .route(.conversations)) {
                        iPadDestination(.route(.conversations), session: session)
                    }
                }
                .badge(unreadConversations)
                .customizationID("aloha.tab.conversations")
                Tab("Discover", systemImage: "safari", value: SidebarItem.route(.explore)) {
                    LazyShellContent(isSelected: sidebarItem == .route(.explore)) {
                        iPadDestination(.route(.explore), session: session)
                    }
                }
                .customizationID("aloha.tab.explore")
                // The long tail, folded. Up to eighteen rows used to stand
                // in the sidebar, the places visited weekly among the ones
                // visited every few minutes; the feeds and what comes to you
                // stay in view and the rest are one tap further, in one
                // section that starts closed and stays as it is left. Nothing
                // is gone: each row can still be pinned to the tab bar, and
                // the account menu at the sidebar's foot keeps its own way in.
                TabSection {
                    sidebarTab(
                        "My profile", symbol: "person.crop.circle",
                        route: .profile(accountID: session.snapshot.serverAccountID),
                        session: session)
                    sidebarTab(
                        "Bookmarks", symbol: AlohaSymbol.bookmark, route: .bookmarks,
                        session: session)
                    sidebarTab(
                        "Liked posts", symbol: AlohaSymbol.favourite, route: .favourites,
                        session: session)
                    sidebarTab(
                        "Your lists", symbol: "list.bullet.rectangle", route: .lists,
                        session: session)
                    if session.capabilities.collections {
                        sidebarTab(
                            "Collections", symbol: "rectangle.stack",
                            route: .collections(accountID: nil), session: session)
                    }
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
                } header: {
                    Text("More", comment: "iPad sidebar section holding the less used places")
                }
                .customizationID("aloha.section.more")
                .defaultSectionExpansion(.collapsed)
                Tab(
                    "Search", systemImage: "magnifyingglass",
                    value: SidebarItem.route(.search(query: nil)), role: .search
                ) {
                    LazyShellContent(
                        isSelected: sidebarItem == .route(.search(query: nil))
                    ) {
                        iPadDestination(.route(.search(query: nil)), session: session)
                    }
                }
                .customizationID("aloha.tab.search")
            }
            .tabViewStyle(.sidebarAdaptable)
            .tabViewCustomization($tabCustomization)
            // The window's width, not the column's: whether the sidebar is
            // showing should not make an open thread jump between a column
            // and a push.
            .onGeometryChange(for: Bool.self) {
                ShellLayout.showsDetailColumn(forWindowWidth: $0.size.width)
            } action: { isAvailable in
                isDetailColumnAvailable = isAvailable
            }
            .tabViewSidebarBottomBar {
                AccountMenuButton(
                    session: session, onOpen: open,
                    onAddAccount: { presentSignIn() },
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
                LazyShellContent(isSelected: sidebarItem == .route(route)) {
                    iPadDestination(.route(route), session: session)
                }
            }
            .customizationID(ShellTab.customizationID(for: route))
            .defaultVisibility(.hidden, for: .tabBar)
        }

        private func iPadDestination(_ item: SidebarItem, session: AccountSession) -> some View {
            let detailRoot = showsDetailColumn ? detailPaths[item]?.first : nil
            return AnyView(
                HStack(spacing: 0) {
                    NavigationStack(path: sidebarPath(item)) {
                        Group {
                            switch item {
                            case .mode(let mode): modeRoot(mode, session: session)
                            case .route(let route):
                                destination(route, session: session, isRoot: true)
                            }
                        }
                        .navigationDestination(for: Route.self) {
                            destination($0, session: session)
                        }
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            iPadAccountToolbar(session)
                            composeToolbar
                        }
                        .alohaWindowGround(palette)
                    }
                    .frame(maxWidth: .infinity)

                    if let detailRoot {
                        Divider()
                            .ignoresSafeArea()
                        detailColumn(item, root: detailRoot, session: session)
                            .containerRelativeFrame(.horizontal) { width, _ in
                                ShellLayout.detailColumnWidth(forWindowWidth: width)
                            }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.smooth(duration: 0.25), value: detailRoot == nil))
        }

        /// The detail column: the post or profile opened from the primary
        /// column, on a stack of its own. Its screens are built by a copy of
        /// the shell marked `.detail`, so what they open is pushed here too.
        private func detailColumn(
            _ item: SidebarItem, root: Route, session: AccountSession
        ) -> some View {
            var detail = self
            detail.column = .detail
            return NavigationStack(path: detailPath(item)) {
                detail.destination(root, session: session)
                    // A different post is a different screen: every screen
                    // keeps its model in `@State`, which a new route in the
                    // same place would otherwise inherit.
                    .id(root)
                    .navigationDestination(for: Route.self) {
                        detail.destination($0, session: session)
                    }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                closeDetailColumn(item)
                            } label: {
                                Label {
                                    Text("Close", comment: "Detail column action")
                                } icon: {
                                    Image(systemName: "xmark")
                                }
                            }
                            .help(Text("Close", comment: "Detail column action"))
                        }
                    }
            }
            .alohaWindowGround(palette)
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
                    onAddAccount: { presentSignIn() },
                    showsBrowseDestinations: isCompact, usesCompactMenu: !isCompact)
            }
        }
    #endif

    #if os(iOS) || os(visionOS)
        /// A tab's screen, built the first time the tab is selected.
        ///
        /// `TabView` evaluates the content of every tab while it is being
        /// created. Each of these contents builds a `NavigationStack` around
        /// the whole destination switch, and on a real iPad constructing all
        /// of them at once overran the main thread's stack before the first
        /// frame was drawn. The screen is kept once built, so leaving a tab
        /// and coming back still finds it where it was. The visionOS shell's
        /// tabs are built the same way, for the same reason.
        struct LazyShellContent<Content: View>: View {
            let isSelected: Bool
            @ViewBuilder let content: () -> Content
            @State private var hasLoaded = false

            var body: some View {
                Group {
                    if hasLoaded {
                        content()
                    } else {
                        Color.clear
                    }
                }
                .onChange(of: isSelected, initial: true) { _, selected in
                    if selected { hasLoaded = true }
                }
            }
        }
    #endif

    // MARK: - iPad, Mac, Vision

    func splitShell(_ session: AccountSession) -> some View {
        splitView {
            SidebarView(
                session: session,
                selection: $sidebarItem,
                selectedSource: $selectedSource,
                onAddAccount: { presentSignIn() },
                onSwitchAccount: { switchAccount(to: $0) }
            )
            .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 320)
        } detail: {
            HStack(spacing: 0) {
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
                #if os(macOS)
                    // On the stack rather than its root, so the field stays in
                    // the toolbar while a post or a profile is pushed.
                    .modifier(
                        GlobalSearchField(
                            isShown: !hasOwnSearchField(sidebarItem), text: $searchText,
                            isFocused: $isSearchFocused
                        ) { query in
                            sidebarItem = .route(.search(query: query.isEmpty ? nil : query))
                        }
                    )
                #endif
                // A stack per sidebar row, as on iPad: each row keeps what was
                // pushed on it. A fresh stack for each row rather than one stack
                // whose path is swapped, which would animate as a pop and a push.
                .id(sidebarItem)
                #if os(macOS)
                    // A place arrives rather than replacing the last one in a
                    // single frame.
                    .transition(.opacity.combined(with: .offset(y: 8)))
                #endif
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                // The window's own ground, not the system's. A reading column is
                // centred in this space, and without this the space around it was
                // window background — a cool white the app never uses — so the
                // column read as a sheet of paper dropped on the wrong desk.
                .alohaWindowGround(palette)
                #if os(macOS)
                    if showsContextColumn, sidebarItem == .mode(.home), !showsDeck,
                        windowWidth >= ShellLayout.contextColumnMinimumWidth,
                        detailPaths[sidebarItem]?.isEmpty ?? true
                    {
                        Divider().ignoresSafeArea()
                        ContextColumn(session: session) { open($0) }
                            .frame(width: 270)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    if showsDetailColumn, let opened = detailPaths[sidebarItem],
                        let top = opened.last
                    {
                        Divider().ignoresSafeArea()
                        macDetailColumn(top, depth: opened.count, session: session)
                            .frame(
                                width: ShellLayout.detailColumnWidth(forWindowWidth: windowWidth)
                            )
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                #endif
            }
            #if os(macOS)
                .animation(
                    .smooth(duration: 0.25), value: detailPaths[sidebarItem]?.isEmpty ?? true
                )
                .animation(.easeOut(duration: 0.2), value: sidebarItem)
                .animation(.smooth(duration: 0.25), value: showsContextColumn)
            #endif
        }
        #if os(macOS)
            // The whole window's width, sidebar included: whether there is
            // room for a post beside the list it was opened from.
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: { width in
                windowWidth = width
                isDetailColumnAvailable = width >= ShellLayout.macDetailColumnMinimumWidth
            }
        #endif
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

    #if os(macOS)
        /// The post or profile opened from the list, beside it, in a window
        /// wide enough for both — the iPad's detail column on the Mac.
        ///
        /// Not a navigation stack of its own: a Mac window has one toolbar,
        /// and a second stack would put its title and buttons into it beside
        /// the list's. The column carries its own small bar instead — back
        /// through what was opened inside it, and close.
        private func macDetailColumn(
            _ route: Route, depth: Int, session: AccountSession
        ) -> some View {
            var detail = self
            detail.column = .detail
            return VStack(spacing: 0) {
                HStack(spacing: AlohaMetrics.space2) {
                    if depth > 1 {
                        Button {
                            goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .help(Text("Back", comment: "Menu item"))
                    }
                    Spacer()
                    Button {
                        closeDetailColumn(sidebarItem)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .help(Text("Close", comment: "Detail column action"))
                    .keyboardShortcut(.cancelAction)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, AlohaMetrics.space3)
                .padding(.vertical, AlohaMetrics.space2)

                Divider()

                detail.destination(route, session: session)
                    // A different post is a different screen, as on iPad.
                    .id(route)
                    // Opening a post beside the list leaves the keyboard on
                    // the list, as Mail's reading pane does.
                    .environment(\.statusListTakesFocus, false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(palette.background)
        }
    #endif

    #if os(macOS)
        /// A window opened for one destination: that screen as the root of
        /// a stack of its own, and what is opened from it pushed on top.
        func routeWindowShell(_ session: AccountSession) -> some View {
            NavigationStack(path: sidebarPath(sidebarItem)) {
                Group {
                    if let initialRoute {
                        destination(initialRoute, session: session, isRoot: true)
                    }
                }
                .navigationDestination(for: Route.self) { destination($0, session: session) }
            }
            .alohaWindowGround(palette)
            // Titled by whose post it is, like a message window is titled by
            // its subject, rather than every window reading "Post".
            .environment(\.titlesWindowByAuthor, true)
            .frame(minWidth: 420, minHeight: 360)
        }
    #endif

    /// The split view, with its columns under the shell's control on the
    /// Mac so the mini timeline can open without its sidebar.
    private func splitView(
        @ViewBuilder sidebar: () -> some View, @ViewBuilder detail: () -> some View
    ) -> some View {
        #if os(macOS)
            NavigationSplitView(
                columnVisibility: $columnVisibility, sidebar: sidebar, detail: detail
            )
            .onAppear {
                if isMiniWindow { columnVisibility = .detailOnly }
            }
        #else
            NavigationSplitView(sidebar: sidebar, detail: detail)
        #endif
    }

    /// The screens that search themselves — conversations, people, search —
    /// and so show their own field where the app-wide one would be.
    func hasOwnSearchField(_ item: SidebarItem) -> Bool {
        switch item {
        case .route(.conversations), .route(.explore), .route(.search): true
        default: false
        }
    }

    @ToolbarContentBuilder
    var composeToolbar: some ToolbarContent {
        #if os(iOS)
            ToolbarItem(id: "compose-post", placement: composeToolbarPlacement) {
                composeButton
            }
            .matchedTransitionSource(id: ComposeTransition.sourceID, in: composeTransition)
        #else
            // No identifier off iOS. The root screen and a pushed one each
            // declare this button, and for the length of a push both are in
            // the window's toolbar at once: an `NSToolbar` refuses two items
            // with one identifier, by exception, so opening a profile or a
            // thread from a timeline took the Mac app down.
            ToolbarItem(placement: composeToolbarPlacement) {
                composeButton
            }
            #if os(macOS)
                if sidebarItem == .mode(.home), !showsDeck, column == .primary {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showsContextColumn.toggle()
                        } label: {
                            Label {
                                if showsContextColumn {
                                    Text("Hide Trends", comment: "Toolbar action")
                                } else {
                                    Text("Show Trends", comment: "Toolbar action")
                                }
                            } icon: {
                                Image(systemName: "sidebar.trailing")
                            }
                        }
                        .help(
                            Text(
                                "Show or hide trends, suggestions and your lists",
                                comment: "Toolbar action help"))
                    }
                }
            #endif
        #endif
    }

    private var composeButton: some View {
        Button {
            composing = ComposerPresentation(fromComposeButton: true)
        } label: {
            Label {
                Text("New post", comment: "Toolbar action")
            } icon: {
                #if os(macOS)
                    // The pencil, not a plus: a Mac toolbar holds a screen's
                    // own "new" beside this one — a new album, a new message —
                    // and two plus signs side by side said nothing about
                    // which was which.
                    Image(systemName: "square.and.pencil")
                #else
                    Image(systemName: AlohaSymbol.compose)
                #endif
            }
        }
        #if !os(macOS)
            .keyboardShortcut("n", modifiers: .command)
        #endif
        // On the Mac ⌘N is File ▸ New Post's, which composes for the window
        // in front; the button claiming it too made the two fight over it.
        .help(Text("New post", comment: "Toolbar action"))
    }

    private var composeToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
            .topBarTrailing
        #else
            .primaryAction
        #endif
    }

    @ViewBuilder
    func modeRoot(_ mode: FeedMode, session: AccountSession) -> some View {
        switch mode {
        case .shorts:
            // Full screen, and there is no source to choose in it.
            ShortsView(session: session, models: feedModels) { handle($0, session: session) }
                .navigationTitle(modeTitle(mode))
                #if os(iOS)
                    .toolbar(.hidden, for: .navigationBar)
                #endif

        case .photos:
            timelineChrome(
                PhotosModeView(session: session, source: selectedSource, models: feedModels) {
                    handle($0, session: session)
                }
                .navigationTitle(modeTitle(mode)),
                session: session)

        case .video:
            timelineChrome(
                VideoModeView(session: session, source: selectedSource, models: feedModels) {
                    handle($0, session: session)
                }
                .navigationTitle(modeTitle(mode)),
                session: session)

        case .audio:
            timelineChrome(
                AudioModeView(session: session, source: selectedSource, models: feedModels) {
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
                NewsModeView(session: session, source: selectedSource, models: feedModels) {
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

        #if os(macOS)
            case .home where showsDeck:
                DeckView(session: session) { handle($0, session: session) }
                    .navigationTitle(modeTitle(mode))
                    .alohaWindowGround(palette)
        #endif

        case .home:
            timelineChrome(
                TimelineView(
                    key: TimelineKey(mode: mode, source: selectedSource),
                    session: session, models: feedModels
                ) { handle($0, session: session) }
                // The home mode is whichever of the three you are reading, so
                // the title says which rather than always "My Feed".
                #if os(macOS)
                    // The Mac's toolbar control says which source; the title
                    // says which screen, as on every other one.
                    .navigationTitle(modeTitle(mode))
                #else
                    .navigationTitle(sourceTitle)
                #endif
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
                    // Only on the phone: the split shell carries the account
                    // drawer at the sidebar's foot. Search is a tab of its own
                    // on both.
                    if !usesSidebar {
                        ToolbarItem(placement: .topBarLeading) {
                            AccountMenuButton(
                                session: session,
                                onOpen: { open($0) },
                                onAddAccount: { presentSignIn() })
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                open(.notifications)
                            } label: {
                                Image(systemName: AlohaSymbol.notifications)
                            }
                            // The count the app icon already wears, where it
                            // can be acted on. Zero draws no badge.
                            .badge(unreadNotifications(session))
                            .accessibilityLabel(activitiesLabel(session))
                            .help(Text("Activities", comment: "Toolbar button"))
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink(value: Route.conversations) {
                                Image(systemName: AlohaSymbol.directMessage)
                            }
                            .badge(unreadConversations)
                            .accessibilityLabel(directMessagesLabel)
                            .help(Text("Direct messages", comment: "Toolbar button"))
                        }
                        // Reading what came in and writing are different kinds
                        // of action; the gap keeps them in separate glass
                        // groups rather than one capsule that reads as one
                        // control.
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                composing = ComposerPresentation(fromComposeButton: true)
                            } label: {
                                Image(systemName: AlohaSymbol.compose)
                            }
                            .keyboardShortcut("n", modifiers: .command)
                            .accessibilityLabel(Text("New post", comment: "Toolbar action"))
                            .help(Text("New post", comment: "Toolbar action"))
                        }
                        .matchedTransitionSource(
                            id: ComposeTransition.sourceID, in: composeTransition)
                    }
                }
            #endif
    }

    private func activitiesLabel(_ session: AccountSession) -> Text {
        let unread = unreadNotifications(session)
        return unread > 0
            ? Text("Activities, \(unread) unread", comment: "Toolbar button with badge")
            : Text("Activities", comment: "Toolbar button")
    }

    private var directMessagesLabel: Text {
        unreadConversations > 0
            ? Text(
                "Direct messages, \(unreadConversations) unread",
                comment: "Toolbar button with badge")
            : Text("Direct messages", comment: "Toolbar button")
    }
}

/// Which of its two screens the phone's search tab is showing.
enum SearchTabScope: Hashable {
    case search
    case discover
}

#if os(macOS)
    /// The Mac's search field in the toolbar, on every screen that does not
    /// search itself (docs/09 §2): type, press Return, and Search opens with
    /// the results. ⌘F puts the cursor in it (`focusSearch`).
    ///
    /// It was a button that jumped to the Search screen, because an earlier
    /// field pushed the notification filter in the toolbar's centre aside;
    /// the screens with a filter of their own search themselves and so show
    /// no field here.
    private struct GlobalSearchField: ViewModifier {
        let isShown: Bool
        @Binding var text: String
        var isFocused: FocusState<Bool>.Binding
        let onSubmit: (String) -> Void

        func body(content: Content) -> some View {
            if isShown {
                content
                    .searchable(
                        text: $text, placement: .toolbar,
                        prompt: Text("Search", comment: "Toolbar search field")
                    )
                    .searchFocused(isFocused)
                    .onSubmit(of: .search) {
                        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        // The query moves to the Search screen's own field;
                        // this one is left empty for the next search.
                        text = ""
                        onSubmit(query)
                    }
            } else {
                content
            }
        }
    }
#endif
