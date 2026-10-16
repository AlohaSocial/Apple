// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Applies the theme before the shell reads its palette, including presentations.
public struct AppShell: View {
    @Environment(AppEnvironment.self) private var environment
    private let initialRoute: Route?

    /// `initialRoute` opens the shell already showing a destination — a
    /// window of its own for a thread or a profile (see `RouteWindow`).
    public init(initialRoute: Route? = nil) {
        self.initialRoute = initialRoute
    }

    public var body: some View {
        ThemedAppShell(initialRoute: initialRoute)
            .alohaTheme(
                environment.theme, metrics: environment.metrics, accent: environment.serverAccent)
    }
}

/// The root. A tab bar on iPhone, a split view everywhere else.
private struct ThemedAppShell: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.alohaPalette) private var palette

    /// A tab bar selection that can be a mode *or* one of the other tabs.
    private typealias TabSelection = ShellTab

    @State private var selectedTab: TabSelection = .mode(.home)
    @State private var selectedMode: FeedMode = .home
    @State private var sidebarItem: SidebarItem = .mode(.home)
    @State private var selectedSource: TimelineSource = .home
    /// What each phone tab has pushed, so leaving a tab and coming back
    /// finds the screen you left there. One shared path made a screen pushed
    /// on one tab turn up on the next.
    @State private var tabPaths: [TabSelection: [Route]] = [:]
    /// The same, per sidebar row, for the iPad, Mac and Vision shells.
    @State private var sidebarPaths: [SidebarItem: [Route]] = [:]
    /// Where this scene was, rewritten as it changes (`ShellRestoration`).
    @SceneStorage("aloha.shell.restoration") private var storedRestoration: Data?
    /// Nothing is written back until the stored state has been read, or the
    /// first launch's empty shell would overwrite it.
    @State private var hasRestored = false
    @State private var isPresentingSignIn = false
    /// The address typed on the introduction, for the sign-in screen to open
    /// with — or empty when the person chose "skip" and will type it there.
    @State private var signInAddress = ""
    /// The terms sheet, shown after the introduction rather than before it.
    /// The first thing a person should see is what the app is; the rules
    /// belong after that, once they care (docs/09 §4).
    @State private var isShowingTerms = false
    /// Which feeds the person wants, chosen once after the first sign-in.
    /// Nil once the choice has been made.
    @State private var chosenModes: Set<FeedMode>?
    @State private var composing: ComposerPresentation?
    @State private var isComposingStory = false
    @Namespace private var mediaTransition
    @State private var isCelebrating = false
    @State private var mediaPresentation: MediaPresentation?
    @State private var reportTarget: ReportTarget?
    @State private var hasAcceptedTerms = TermsGate.hasAccepted
    @State private var translator = Translator()
    @State private var editing: EditRequest?
    @State private var deleting: Status?
    @State private var confirming: ModerationRequest?
    @State private var sheet: ShellSheet?
    /// The Focus filter last applied, so it is applied once per change.
    @State private var appliedFocus = FocusFilterState.none
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURLAction
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    /// Unread conversations, as the messages list last counted them. Read
    /// through `@AppStorage` so the Messages badge moves the moment that list
    /// writes a new count, rather than when this view happens to redraw.
    @AppStorage(AppGroup.unreadConversationsKey, store: AppGroup.defaults)
    private var unreadConversations = 0
    #if os(iOS)
        /// Which places a person pinned to the iPad's tab bar, and in what order.
        @AppStorage("aloha.iPad.tabCustomization")
        private var tabCustomization = TabViewCustomization()
    #endif

    /// Set on a window opened for one destination. Such a window shows it and
    /// otherwise stays out of the way: the app-wide requests — compose, open a
    /// route, add an account — are for the main window, or every open thread
    /// window would answer them too.
    private let initialRoute: Route?

    /// The account load and the sync engine are the process's, not a
    /// window's: loading again from a second window would replace the
    /// sessions the first one is showing.
    private static var hasStarted = false

    init(initialRoute: Route? = nil) {
        self.initialRoute = initialRoute
    }

    var body: some View { content }

    private var content: some View {
        root
            .overlay {
                if isCelebrating { ConfettiView(isFalling: isCelebrating) }
            }
            #if os(iOS)
                // The watch follows the active account and its colour; both
                // can change without the other, so both are the trigger.
                .onChange(
                    of: WatchTrigger(
                        account: environment.activeSession?.id, accent: environment.serverAccent),
                    initial: true
                ) {
                    WatchBridge.shared.activate()
                    WatchBridge.shared.send(environment.watchPairing())
                }
            #endif
            .onChange(of: environment.activeSession?.lastPosted?.id) { _, id in
                guard id != nil, FirstPost.isStillToCome else { return }
                FirstPost.recordPosted()
                isCelebrating = true
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    isCelebrating = false
                }
            }
            .environment(\.mediaTransition, mediaTransition)
            .modifier(
                ShellSheets(
                    isPresentingSignIn: $isPresentingSignIn,
                    signInAddress: $signInAddress,
                    composing: $composing,
                    reportTarget: $reportTarget,
                    editing: $editing,
                    mediaPresentation: $mediaPresentation,
                    sheet: $sheet)
            )
            .modifier(ShellAlerts(deleting: $deleting, confirming: $confirming))
            // 9: the Translation framework's session is attached to a view, so
            // the host sits where every status can reach it.
            .translationHost(translator)
            .environment(translator)
            .task { await start() }
            .onChange(of: restoration) { _, restoration in
                storedRestoration = restoration?.encoded()
            }
            .onChange(of: environment.activeSession?.id) { previous, current in
                // Another account's pushed screens mean nothing on this one:
                // a thread id from one server is a stranger's post, or none,
                // on the next.
                guard previous != nil, previous != current else { return }
                tabPaths = [:]
                sidebarPaths = [:]
            }
            .onChange(of: scenePhase) { _, phase in
                // A socket closes on background immediately; BGAppRefreshTask
                // takes over from there (docs/08 §6).
                environment.sync.setForeground(phase == .active)
                if phase == .active { Task { await environment.sendQueue.drainAll() } }
                if phase == .active { refreshMemoriesWidget() }
                // An intent with `openAppWhenRun` brings a running app to the
                // front rather than launching it, so `start()` never sees
                // what it left behind; this does.
                if phase == .active, let pending = IntentNavigation.take() { open(pending) }
                if phase == .active { applyFocusFilter() }
            }
            .onReceive(NotificationCenter.default.publisher(for: IntentNavigation.focusChanged)) {
                _ in applyFocusFilter()
            }
            .onReceive(NotificationCenter.default.publisher(for: IntentNavigation.routeRequested)) {
                _ in
                // A tapped notification, or an intent run in this process.
                if let pending = IntentNavigation.take() { open(pending) }
            }
            .onOpenURL { url in handle(url) }
            .onReceive(NotificationCenter.default.publisher(for: RouteResolver.composeRequested)) {
                note in
                // The compose deep link — from the quick-compose widget, a
                // Shortcut, or a draft handed off from another device —
                // reached here because the composer is a sheet the shell owns,
                // not a navigation destination.
                guard initialRoute == nil, environment.activeSession != nil else { return }
                composing = ComposerPresentation(
                    draftText: note.userInfo?["draft"] as? String ?? "")
            }
            .onReceive(
                NotificationCenter.default.publisher(for: RouteResolver.storyComposerRequested)
            ) { _ in
                // Stories are a Nextcloud Social extension; on any other
                // server the control opens the app and nothing more.
                guard initialRoute == nil,
                    environment.activeSession?.capabilities.stories == true
                else { return }
                isComposingStory = true
            }
            .sheet(isPresented: $isComposingStory) {
                if let session = environment.activeSession {
                    StoryComposerSheet(session: session, onPosted: {})
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .alohaOpenRoute)) { note in
                // Where Handoff arrives.
                guard initialRoute == nil else { return }
                if let route = note.userInfo?["route"] as? Route { open(route) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .alohaAddAccount)) { _ in
                // Where the Settings scene's "Add account" row arrives: the
                // sign-in sheet belongs to this shell, wherever the request
                // came from.
                guard initialRoute == nil else { return }
                isPresentingSignIn = true
            }
            // The menu bar acts on the window in front (see `ShellCommands`).
            .focusedSceneValue(\.shellCommands, shellCommands)
    }

    /// What a person sees, in the order it is fair to ask it of them:
    ///
    /// 1. the introduction — what this app is, and where to sign in;
    /// 2. only then the terms, which nobody can agree to before they know
    ///    what they are agreeing inside;
    /// 3. the feeds they want, once there is a server whose answer to that
    ///    question is knowable;
    /// 4. the app.
    ///
    /// This used to lead with the terms, so the first screen a person ever
    /// saw was a page of dense rules — which is why the introduction behind
    /// it read as if it were not there.
    @ViewBuilder
    private var root: some View {
        if environment.isLoading {
            // Not a bare spinner: the app is saying what it is while it
            // loads, which is the only thing it can honestly say yet.
            VStack(spacing: AlohaMetrics.space4) {
                AnimatedAlohaLogoMark(size: 96)
                Text("Aloha Social", comment: "App name")
                    .font(AlohaType.wordmark.weight(.bold))
                    .fontDesign(.rounded)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background)
        } else if let session = environment.activeSession {
            shell(session)
                // Switching accounts has to change view identity: every
                // timeline holds its model in `@State`, and without this the
                // previous account's posts stay on screen and its client keeps
                // serving the actions (docs/03 §6).
                .id(session.id)
                // Deciding which feeds a first session gets belongs to the
                // moment the shell appears, not to the evaluation of this
                // body: `chosenModes` is state, and a `@ViewBuilder` will not
                // take a statement that returns `()` anyway.
                .onAppear {
                    repairFeedSelection(session.visibleModes)
                    promptForModesIfNeeded(session)
                }
                .onChange(of: session.visibleModes) { _, modes in
                    repairFeedSelection(modes)
                }
                .sheet(
                    item: Binding(
                        get: { self.chosenModes.map { ModeSelection(modes: $0) } },
                        set: { newValue in
                            if newValue == nil { self.chosenModes = nil }
                        })
                ) { selection in
                    NavigationStack {
                        ModeSelectionView(
                            selected: Binding(
                                get: { selection.modes },
                                set: { newValue in self.chosenModes = newValue }),
                            capabilities: session.capabilities,
                            onContinue: {
                                finishModeSelection(session)
                            }
                        )
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button {
                                    finishModeSelection(session)
                                } label: {
                                    Text("Continue", comment: "Settings action")
                                        .font(.body.weight(.semibold))
                                }
                                .disabled(
                                    self.chosenModes == nil || self.chosenModes?.isEmpty == true)
                            }
                        }
                    }
                }
        } else if !hasAcceptedTerms {
            introduction(offeringTerms: true)
        } else {
            introduction(offeringTerms: false)
        }
    }

    /// Offers the mode choice once, after the first sign-in — the one point at
    /// which the server's answer to "which feeds exist" is knowable. Without
    /// this `ModeSelectionView` was dead code that never appeared.
    private func promptForModesIfNeeded(_ session: AccountSession) {
        guard chosenModes == nil else { return }
        guard UserDefaults.standard.stringArray(forKey: Self.chosenModesKey) == nil else {
            return
        }
        chosenModes = Set(session.visibleModes)
    }

    private func finishModeSelection(_ session: AccountSession) {
        guard let chosenModes, !chosenModes.isEmpty else { return }
        let ordered = FeedMode.allCases.filter {
            chosenModes.contains($0) && session.capabilities.supports($0)
        }
        guard !ordered.isEmpty else { return }
        self.chosenModes = nil
        Task {
            await session.updateSettings { $0.enabledModes = ordered }
            Self.recordChosenModes(Set(ordered))
        }
    }

    /// A removed feed must not remain the selection of a tab that no longer exists.
    private func repairFeedSelection(_ modes: [FeedMode]) {
        guard let fallback = modes.first else { return }
        if !modes.contains(selectedMode) { selectedMode = fallback }
        if case .mode(let mode) = selectedTab, !modes.contains(mode) {
            selectedTab = .mode(fallback)
            tabPaths[.mode(mode)] = nil
        }
        // One feed more can leave Activities without room on the tab bar.
        if selectedTab == .notifications,
            !ShellTab.showsNotificationsTab(feedCount: modes.count)
        {
            selectedTab = .mode(fallback)
            tabPaths[.notifications] = nil
        }
        if case .mode(let mode) = sidebarItem, !modes.contains(mode) {
            sidebarItem = .mode(fallback)
            sidebarPaths[.mode(mode)] = nil
        }
    }

    /// The introduction, and — for a first launch only — the terms behind it.
    private func introduction(offeringTerms: Bool) -> some View {
        WelcomeView { address in
            signInAddress = address ?? ""
            if offeringTerms {
                isShowingTerms = true
            } else {
                isPresentingSignIn = true
            }
        }
        .sheet(isPresented: $isShowingTerms) {
            TermsGate(
                onAccept: {
                    isShowingTerms = false
                    isPresentingSignIn = true
                },
                onDecline: { isShowingTerms = false })
        }
    }

    /// The feeds chosen once, so `chosenModes` can hold a value.
    private struct ModeSelection: Hashable, Identifiable {
        let modes: Set<FeedMode>
        var id: String { "mode-selection" }
    }

    private static let chosenModesKey = "aloha.chosenModes"

    private static func recordChosenModes(_ modes: Set<FeedMode>) {
        UserDefaults.standard.set(
            modes.map(\.rawValue).sorted(), forKey: chosenModesKey)
    }

    private func start() async {
        guard !Self.hasStarted else {
            // Another window of a running app: the environment is loaded,
            // but this scene still has its own place to come back to.
            if let initialRoute { open(initialRoute) } else { restoreShell() }
            return
        }
        Self.hasStarted = true
        await environment.loadIfNeeded()
        #if DEBUG
            if MockMode.isEnabled {
                await MockMode.seedIfNeeded(environment)
                hasAcceptedTerms = !MockMode.startsSignedOut
            }
        #endif
        environment.sync.attach(to: environment)
        environment.sync.start()
        environment.sendQueue.attach(to: environment)
        environment.notifier.registerCategories()
        AlohaTips.configure()
        refreshMemoriesWidget()
        // Permission is asked once an account exists — there is nothing to
        // notify about before that, and a prompt on the welcome screen is the
        // pattern Apple's guidance says not to use.
        var shouldAsk = environment.hasAccounts
        #if DEBUG
            if MockMode.isEnabled { shouldAsk = false }
        #endif
        // Whether they said yes is the notifier's to remember; the shell only
        // has to have asked once.
        if shouldAsk { _ = await environment.notifier.requestAuthorisation() }
        restoreShell()
        // An intent that opened the app left its destination behind, and it
        // outranks wherever the scene was.
        if let pending = IntentNavigation.take() { open(pending) }
        if let initialRoute { open(initialRoute) }
    }

    /// Puts back the tab, the sidebar row and what was pushed on each.
    private func restoreShell() {
        defer { hasRestored = true }
        #if DEBUG
            // The screen tours start every test from the top, not from
            // wherever the last one left the simulator.
            if MockMode.isEnabled { return }
        #endif
        guard let session = environment.activeSession,
            let restored = ShellRestoration.decode(storedRestoration, for: session.id)
        else { return }
        tabPaths = restored.tabPaths
        sidebarPaths = restored.restoredSidebarPaths
        selectedTab = restored.tab
        sidebarItem = restored.sidebarItem.item
        if usesSidebar {
            if case .mode(let mode) = sidebarItem { selectedMode = mode }
        } else if case .mode(let mode) = selectedTab {
            selectedMode = mode
        }
        repairFeedSelection(session.visibleModes)
    }

    /// What the scene would restore to now; nil until the stored state has
    /// been read back, so that read cannot be overwritten before it happens.
    private var restoration: ShellRestoration? {
        guard hasRestored, let id = environment.activeSession?.id else { return nil }
        return ShellRestoration(
            accountID: id, tab: selectedTab, tabPaths: tabPaths,
            sidebarItem: sidebarItem, sidebarPaths: sidebarPaths)
    }

    /// Whether Activities is a tab of its own on this phone, or stays in the
    /// account menu because a tab would push the bar past five.
    private var showsNotificationsTab: Bool {
        environment.activeSession.map {
            ShellTab.showsNotificationsTab(feedCount: $0.visibleModes.count)
        } ?? false
    }

    private func unreadNotifications(_ session: AccountSession) -> Int {
        environment.sync.unreadCounts[session.id] ?? 0
    }

    private func tabPath(_ tab: TabSelection) -> Binding<[Route]> {
        Binding(get: { tabPaths[tab, default: []] }, set: { tabPaths[tab] = $0 })
    }

    private func sidebarPath(_ item: SidebarItem) -> Binding<[Route]> {
        Binding(get: { sidebarPaths[item, default: []] }, set: { sidebarPaths[item] = $0 })
    }

    /// Writes today's "on this day" for the Memories widget, once per day and
    /// account; a no-op when it is already there.
    private func refreshMemoriesWidget() {
        #if DEBUG
            // The tours' mock server has no memories worth a widget.
            if MockMode.isEnabled { return }
        #endif
        guard let session = environment.activeSession else { return }
        Task(priority: .utility) { await MemoriesWidgetWriter.refreshIfStale(session) }
    }

    /// Applies the Focus filter once per change: the account it keeps the app
    /// on, and the feed it opens to. Applied on every activation it would
    /// pull the reader back to that feed each time they came back.
    private func applyFocusFilter() {
        let focus = FocusFilterState.current
        guard focus != appliedFocus else { return }
        appliedFocus = focus
        if let accountID = focus.accountID { environment.setActiveAccount(accountID) }
        // Only a feed this account actually shows: a Focus set up for a mode
        // the server has no surface for would leave a tab that is not there.
        if let mode = focus.mode, environment.activeSession?.visibleModes.contains(mode) == true {
            open(.timeline(TimelineKey(mode: mode, source: .home)))
        }
    }

    func open(_ route: Route) {
        if case .timeline(let key) = route {
            selectedMode = key.mode
            selectedTab = .mode(key.mode)
            sidebarItem = .mode(key.mode)
            selectedSource = key.source
            tabPaths[.mode(key.mode)] = []
            sidebarPaths[.mode(key.mode)] = []
        } else if !usesSidebar, route == .conversations {
            // On a phone direct messages are a tab, not a push.
            selectedTab = .messages
            tabPaths[.messages] = []
        } else if !usesSidebar, route == .notifications, showsNotificationsTab {
            // And so are activities, where the tab bar has room for them.
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
                .conversations, .explore, .lists, .interests,
                .collections(accountID: nil), .notifications, .bookmarks, .settings,
                .search(query: nil),
            ]
        #else
            return SidebarItem.sidebarRoutes
        #endif
    }

    private var usesSidebar: Bool {
        #if os(iOS)
            UIDevice.current.userInterfaceIdiom == .pad
        #else
            true
        #endif
    }
    // Erase at the platform boundary so the root does not embed every tab tree.
    private func shell(_ session: AccountSession) -> AnyView {
        #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone {
                return AnyView(tabShell(session))
            } else {
                return AnyView(iPadShell(session))
            }
        #else
            return AnyView(splitShell(session))
        #endif
    }

    /// Onto the stack of whatever is showing: the current tab on a phone,
    /// the current sidebar row everywhere else.
    private func push(_ route: Route) {
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

    private var shellCommands: ShellCommands? {
        guard let session = environment.activeSession else { return nil }
        return ShellCommands(
            compose: { composing = ComposerPresentation() },
            open: { open($0) },
            back: { goBack() },
            canGoBack: canGoBack,
            places: ShellPlace.sidebarOrder(
                modes: session.visibleModes, includesActivities: hasActivitiesRow,
                modeTitle: modeTitle))
    }

    /// Whether Activities is one of the top places — a row on iPad, a tab on
    /// a phone with room for it. The Mac sidebar reaches it from the menu.
    private var hasActivitiesRow: Bool {
        #if os(iOS)
            usesSidebar || showsNotificationsTab
        #else
            false
        #endif
    }

    // MARK: - iPhone

    #if os(iOS)
        private func tabShell(_ session: AccountSession) -> some View {
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

                Tab(value: TabSelection.messages) {
                    NavigationStack(path: tabPath(.messages)) {
                        ConversationsView(
                            session: session,
                            onAction: { handle($0, session: session) },
                            onOpen: { open($0) }
                        )
                        .navigationDestination(for: Route.self) {
                            destination($0, session: session)
                        }
                    }
                } label: {
                    Image(
                        systemName: selectedTab == .messages
                            ? "envelope.fill" : AlohaSymbol.envelope
                    )
                    Text("Messages", comment: "Tab title")
                }
                .badge(unreadConversations)

                if ShellTab.showsNotificationsTab(feedCount: session.visibleModes.count) {
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
        private func iPadShell(_ session: AccountSession) -> some View {
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
                    "Direct messages", systemImage: "envelope",
                    value: SidebarItem.route(.conversations)
                ) {
                    iPadDestination(.route(.conversations), session: session)
                }
                .badge(unreadConversations)
                .customizationID("aloha.tab.conversations")
                Tab(
                    "Activities", systemImage: AlohaSymbol.notifications,
                    value: SidebarItem.route(.notifications)
                ) {
                    iPadDestination(.route(.notifications), session: session)
                }
                .badge(unreadNotifications(session))
                .customizationID("aloha.tab.notifications")
                Tab("Discover", systemImage: "safari", value: SidebarItem.route(.explore)) {
                    iPadDestination(.route(.explore), session: session)
                }
                .customizationID("aloha.tab.explore")
                TabSection("Library") {
                    sidebarTab(
                        "Your lists", symbol: "list.bullet.rectangle", route: .lists,
                        session: session)
                    if session.capabilities.isNextcloudSocial {
                        sidebarTab(
                            "My interests", symbol: "sparkles", route: .interests,
                            session: session)
                    }
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
                    showsBrowseDestinations: isCompact, usesCompactMenu: !isCompact,
                    showsActivities: false)
            }
        }
    #endif

    // MARK: - iPad, Mac, Vision

    private func splitShell(_ session: AccountSession) -> some View {
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
    private var composeToolbar: some ToolbarContent {
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
            .modifier(TimelineSourceMenu(source: $selectedSource))
            #if os(iOS)
                .toolbar {
                    // Only on the phone: the split shell carries both of these
                    // in the sidebar — the account drawer at its foot, and a
                    // search field at its head.
                    if !usesSidebar {
                        ToolbarItem(placement: .topBarLeading) {
                            AccountMenuButton(
                                session: session,
                                onOpen: { open($0) },
                                onAddAccount: { isPresentingSignIn = true },
                                showsActivities: !showsNotificationsTab,
                                unreadActivities: showsNotificationsTab
                                    ? 0 : unreadNotifications(session))
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink(value: Route.search(query: nil)) {
                                Image(systemName: AlohaSymbol.search)
                            }
                            .keyboardShortcut("f", modifiers: .command)
                            .accessibilityLabel(Text("Search", comment: "Toolbar button"))
                            .help(Text("Search", comment: "Toolbar button"))
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

    /// A screen, root or pushed. `isRoot` is for the sidebar shells, whose
    /// root already wears "New post" and (on iPad) the account menu: a pushed
    /// screen keeps "New post" — writing should never be a Back away — but
    /// not the account menu, which sat beside the Back button there.
    private func destination(
        _ route: Route, session: AccountSession, isRoot: Bool = false
    ) -> some View {
        AnyView(destinationContent(route, session: session))
            .modifier(ContinuityAdvertiser(route: route, session: session))
            .toolbar {
                if usesSidebar && !isRoot { composeToolbar }
            }
    }

    @ViewBuilder
    private func destinationContent(_ route: Route, session: AccountSession) -> some View {
        switch route {
        case .thread(let statusID):
            ThreadView(statusID: statusID, session: session) { handle($0, session: session) }
                .readerColumn
        case .profile(let accountID):
            ProfileView(accountID: accountID, session: session) { handle($0, session: session) }
                .readerColumn
        case .hashtag(let name):
            HashtagTimelineView(name: name, session: session) { handle($0, session: session) }
        case .bookmarks:
            TimelineView(
                key: TimelineKey(mode: .home, source: .bookmarks), session: session
            ) { handle($0, session: session) }
            .navigationTitle(Text("Bookmarks", comment: "Screen title"))
        case .favourites:
            TimelineView(
                key: TimelineKey(mode: .home, source: .favourites), session: session
            ) { handle($0, session: session) }
            .navigationTitle(Text("Liked posts", comment: "Screen title"))
        case .notifications:
            NotificationsView(session: session) { handle($0, session: session) }
                .readerColumn
        case .settings:
            SettingsView(onAddAccount: { isPresentingSignIn = true })
                .readerColumn
        case .explore:
            ExploreView(session: session) { handle($0, session: session) }
        case .search(let query):
            SearchView(session: session, initialQuery: query) { handle($0, session: session) }
                .readerColumn
        case .lists:
            ListsView(session: session)
                .readerColumn
        case .filters:
            FiltersView(session: session)
                .readerColumn
        case .safety:
            SafetyListsView(session: session)
                .readerColumn
        case .conversations:
            ConversationsView(
                session: session,
                onAction: { handle($0, session: session) },
                onOpen: { open($0) })
        case .conversation(let conversation):
            ConversationThreadView(conversation: conversation, session: session) {
                handle($0, session: session)
            }
        case .video(let statusID):
            VideoWatchView(statusID: statusID, session: session) { handle($0, session: session) }
        case .drafts:
            DraftsView(session: session)
        case .scheduledPosts:
            ScheduledPostsView(session: session)
        case .notificationRequests:
            NotificationRequestsView(session: session)
        case .notificationPolicy:
            NotificationPolicyView(session: session)
        case .followRequests:
            FollowRequestsView(session: session) { handle($0, session: session) }
        case .handle(let acct):
            ResolvingProfileView(handle: acct, session: session) { handle($0, session: session) }
        case .timeline(let key):
            TimelineView(key: key, session: session) { handle($0, session: session) }

        // Nextcloud Social surfaces.
        case .interests:
            InterestsView(session: session) { handle($0, session: session) }
        case .memories:
            MemoriesView(session: session) { handle($0, session: session) }
        case .heldPosts:
            HeldPostsView(session: session)
        case .starterPacks:
            StarterPacksView(session: session) { handle($0, session: session) }
        case .starterPack(let slug):
            StarterPackView(slug: slug, session: session) { handle($0, session: session) }
        case .place(let id):
            PlaceView(id: id, session: session) { handle($0, session: session) }
        case .archived:
            ArchivedPostsView(session: session) { handle($0, session: session) }
        case .statistics:
            StatisticsView(session: session)
        case .portfolio:
            PortfolioView(session: session)
        case .migration:
            MigrationView(session: session)
        case .authorizedApps:
            AuthorizedAppsView(session: session)
        case .featuredTags:
            FeaturedTagsView(session: session)
        case .editProfile:
            EditProfileView(session: session)
        case .channels:
            ChannelsView(session: session)
        case .collections(let accountID):
            CollectionsView(session: session, accountID: accountID) { handle($0, session: session) }
        case .followers(let accountID):
            FollowersView(accountID: accountID, kind: .followers, session: session) {
                handle($0, session: session)
            }
        case .following(let accountID):
            FollowersView(accountID: accountID, kind: .following, session: session) {
                handle($0, session: session)
            }
        case .tagged(let accountID):
            TaggedPostsView(accountID: accountID, session: session) { handle($0, session: session) }
        // Surfaces the web app has, or the server serves and nobody drew.
        case .annualReport:
            AnnualReportView(session: session) { handle($0, session: session) }
        case .serverInfo:
            ServerInfoView(session: session)
        case .deleteAccount:
            DeleteAccountView(session: session)
        case .moderation:
            ModerationView(session: session) { handle($0, session: session) }
        case .moderationReports:
            ModerationReportsView(session: session) { handle($0, session: session) }
        case .moderationReport(let id):
            ModerationReportView(reportID: id, session: session) { handle($0, session: session) }
        case .moderationAccounts:
            ModerationAccountsView(session: session) { handle($0, session: session) }
        case .moderationTrends:
            ModerationTrendsView(session: session) { handle($0, session: session) }

        case .quotes(let statusID):
            QuotesView(statusID: statusID, session: session) { handle($0, session: session) }

        case .blueskyFeeds:
            BlueskyFeedsView(session: session)
        case .blueskyFeed(let uri, let name):
            BlueskyFeedTimelineView(uri: uri, name: name, session: session) {
                handle($0, session: session)
            }
        case .blueskySettings:
            BlueskySettingsView(session: session)
        case .linkTimeline(let url, let title):
            LinkTimelineView(url: url, title: title, session: session) {
                handle($0, session: session)
            }
        }
    }

    private var sourceTitle: String {
        switch selectedSource {
        case .local: String(localized: "Local", comment: "Timeline source")
        case .federated: String(localized: "Global", comment: "Timeline source")
        default: String(localized: "My Feed", comment: "Mode title")
        }
    }

    private func modeTitle(_ mode: FeedMode) -> String {
        switch mode {
        // The wording follows Nextcloud Social's own navigation, so the two
        // read as the same product.
        case .home: String(localized: "My Feed", comment: "Mode title")
        case .photos: String(localized: "Photos", comment: "Mode title")
        case .video: String(localized: "Videos", comment: "Mode title")
        case .shorts: String(localized: "Shorts", comment: "Mode title")
        case .news: String(localized: "News", comment: "Mode title")
        case .audio: String(localized: "Audio", comment: "Mode title")
        }
    }

    // MARK: - Actions

    private func handle(_ action: StatusRowAction, session: AccountSession) {
        switch action {
        case .open(let status):
            push(.thread(statusID: status.displayed.id))
        case .watch(let status):
            push(.video(statusID: status.displayed.id))
        case .openProfile(let account):
            push(.profile(accountID: account.id))
        case .openMedia(let status, let index):
            mediaPresentation = MediaPresentation(
                statusID: status.id, attachments: status.mediaAttachments, index: index)
        case .reply(let status):
            composing = ComposerPresentation(replyTo: status.displayed)
        case .followLink(let link):
            switch link {
            case .mention(let accountID, let acct, _):
                push(accountID.map { Route.profile(accountID: $0) } ?? .handle(acct))
            case .hashtag(let name, _):
                push(.hashtag(name))
            case .web(let url):
                openURL(url)
            }
        case .openCard(let card):
            if let url = card.url {
                openURL(url)
            }
        case .report(let status):
            reportTarget = ReportTarget(
                account: status.displayed.account,
                status: status.id.isEmpty ? nil : status)
        case .share(let status):
            share(status)

        case .translate(let status):
            Task { await translator.translate(status, session: session) }

        case .edit(let status):
            Task {
                if let source = await StatusActions.source(of: status, session: session) {
                    editing = EditRequest(status: status.displayed, source: source)
                }
            }

        case .delete(let status):
            deleting = status.displayed

        case .redraft(let status):
            Task {
                if let source = await StatusActions.source(of: status, session: session) {
                    composing = ComposerPresentation(
                        redraft: .init(status: status.displayed, source: source))
                }
            }

        case .block(let account):
            confirming = ModerationRequest(account: account, kind: .block)

        case .mute(let account):
            confirming = ModerationRequest(account: account, kind: .mute)

        case .quote(let status):
            composing = ComposerPresentation(quoting: status.displayed)
        case .showDelivery(let status):
            sheet = .delivery(status.displayed)
        case .showEditHistory(let status):
            sheet = .editHistory(status.displayed)
        case .quoteControls(let status):
            sheet = .quoteControls(status.displayed)
        case .tagPeople(let status):
            sheet = .tagPeople(status.displayed)
        case .addToCollection(let status):
            sheet = .addToCollection(status.displayed)
        case .addToList(let account):
            sheet = .addToList(account)

        default:
            Task { await StatusActions.perform(action, session: session) }
        }
    }

    /// The fallback for a `.share` that did not come from a `ShareLink`.
    /// Every button the app draws is a `ShareLink` now (`StatusShareLink`);
    /// this stays correct for anything that still sends the action.
    private func share(_ status: Status) {
        guard let url = status.displayed.url else { return }
        #if canImport(UIKit)
            let activity = UIActivityViewController(
                activityItems: [url], applicationActivities: nil)
            guard
                let window = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive })?
                    .keyWindow,
                var presenter = window.rootViewController
            else { return }
            // The root is busy while it presents a sheet, and a second
            // presentation from it fails without a word: present from the
            // top of the stack instead.
            while let presented = presenter.presentedViewController { presenter = presented }
            // On iPad the controller is a popover and UIKit raises without an
            // anchor. A centred, arrowless one is honest about having none.
            if let popover = activity.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(
                    x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            presenter.present(activity, animated: true)
        #elseif canImport(AppKit)
            let picker = NSSharingServicePicker(items: [url])
            if let view = NSApplication.shared.keyWindow?.contentView {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
        #endif
    }

    /// Links inside posts and cards open in the browser on every platform.
    /// Without the AppKit branch a tap on a link did nothing on the Mac:
    /// the UIKit-only `open` compiled away and the action fell through
    /// silently, so no web content was reachable from a timeline there.
    private func openURL(_ url: URL) {
        LinkOpening.open(url, with: openURLAction)
    }

    private func handle(_ url: URL) {
        // The browser fallback for sign-in comes back this way, and it is not
        // a navigation destination.
        if WebAuthenticator.shared.deliver(url) { return }

        // The composers are presented, not pushed (docs/09 §8): a link asking
        // for one is a request to open the sheet, which is what the
        // quick-compose widget and the Control Center controls do.
        if let presentation = RouteResolver.presentation(for: url) {
            NotificationCenter.default.post(name: presentation.notification, object: nil)
            return
        }

        guard let destination = RouteResolver.destination(for: url) else { return }
        // A Spotlight result or a widget row names its account; the post id
        // in it means nothing under another one.
        if let accountID = destination.accountID { environment.setActiveAccount(accountID) }
        // The same decisions a route from anywhere else gets: a timeline
        // selects its tab, a root destination its tab or row.
        open(destination.route)
    }
}

struct EditRequest: Identifiable, Hashable {
    let status: Status
    let source: StatusSource
    var id: String { status.id }
}

/// Blocking and muting are destructive and federate, so both are confirmed.
public struct ModerationRequest: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable, Hashable { case block, mute }

    public let account: Account
    public let kind: Kind
    public var id: String { account.id + String(describing: kind) }

    var title: String {
        switch kind {
        case .block:
            String(localized: "Block \(account.bestDisplayName)?", comment: "Block confirmation")
        case .mute:
            String(localized: "Mute \(account.bestDisplayName)?", comment: "Mute confirmation")
        }
    }

    var detail: String {
        switch kind {
        case .block:
            String(
                localized:
                    "They won't be able to follow you or see your posts, and you won't see theirs.",
                comment: "Block explanation")
        case .mute:
            String(
                localized: "You won't see their posts. They won't be told.",
                comment: "Mute explanation")
        }
    }
}

struct ReportTarget: Identifiable, Hashable {
    let account: Account
    let status: Status?
    var id: String { account.id + (status?.id ?? "") }
}

struct MediaPresentation: Identifiable, Hashable {
    let statusID: String
    let attachments: [MediaAttachment]
    let index: Int
    var id: String { "\(statusID)-\(index)" }
}

extension View {
    /// A timeline on a regular-width shell is a reading column.
    ///
    /// Full window width runs a post's text to twelve hundred point, which is
    /// unreadable — the eye cannot find the start of the next line. Mail and
    /// Reader constrain their columns, and so does this: 820 points on iPad
    /// and 680 on Mac, centred, with the rest of the window quiet around it.
    /// In compact width — a phone, or an iPad in Slide Over or a narrow
    /// window — the screen is already a column and the constraint would only
    /// add margins, so it does nothing there. The size class decides, not
    /// the device: an iPad can be either.
    var readerColumn: some View {
        #if os(iOS)
            modifier(ReaderColumn(width: 820))
        #else
            modifier(ReaderColumn(width: 680))
        #endif
    }

    /// `fullScreenCover` does not exist on macOS; a sheet is the right
    /// equivalent there.
    @ViewBuilder
    func fullScreenCoverIfAvailable<Item: Identifiable, Content: View>(
        item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(macOS)
            // A sheet, and macOS would run two sheets without it: a window
            // behind a sheet must be resizable to look like a normal window
            // at all, and the media viewer is full-screen on every other
            // platform, so it takes the window here.
            self.sheet(item: item, content: content)
        #else
            fullScreenCover(item: item, content: content)
        #endif
    }
}

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

#if os(iOS)
    private struct WatchTrigger: Equatable {
        var account: UUID?
        var accent: AlohaThemeModifier.ServerTheme?
    }
#endif
/// The surrounding canvas must inherit the same theme as the reading surface.
private struct ReaderColumn: ViewModifier {
    @Environment(\.alohaPalette) private var palette
    #if !os(macOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    let width: CGFloat

    func body(content: Content) -> some View {
        if isCompact {
            content
        } else {
            content
                .frame(maxWidth: width)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .alohaWindowGround(palette)
        }
    }

    private var isCompact: Bool {
        #if os(macOS)
            false
        #else
            horizontalSizeClass == .compact
        #endif
    }
}
