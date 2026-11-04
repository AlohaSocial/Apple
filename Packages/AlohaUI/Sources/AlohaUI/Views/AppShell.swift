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
struct ThemedAppShell: View {
    @Environment(AppEnvironment.self) var environment
    @Environment(\.alohaPalette) var palette

    /// A tab bar selection that can be a mode *or* one of the other tabs.
    typealias TabSelection = ShellTab

    @State var selectedTab: TabSelection = .mode(.home)
    @State var selectedMode: FeedMode = .home
    @State var sidebarItem: SidebarItem = .mode(.home)
    @State var selectedSource: TimelineSource = .home
    /// What each phone tab has pushed, so leaving a tab and coming back
    /// finds the screen you left there. One shared path made a screen pushed
    /// on one tab turn up on the next.
    @State var tabPaths: [TabSelection: [Route]] = [:]
    /// The same, per sidebar row, for the iPad, Mac and Vision shells.
    @State var sidebarPaths: [SidebarItem: [Route]] = [:]
    /// A route opened while the account was being switched, held until the
    /// shell has reset for the account it belongs to.
    @State var accountSwitch = AccountSwitchNavigation()
    /// Where this scene was, rewritten as it changes (`ShellRestoration`).
    @SceneStorage("aloha.shell.restoration") private var storedRestoration: Data?
    /// Nothing is written back until the stored state has been read, or the
    /// first launch's empty shell would overwrite it.
    @State private var hasRestored = false
    @State var isPresentingSignIn = false
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
    @State var composing: ComposerPresentation?
    @State private var isComposingStory = false
    @Namespace private var mediaTransition
    @State private var isCelebrating = false
    @State var mediaPresentation: MediaPresentation?
    @State var reportTarget: ReportTarget?
    @State private var hasAcceptedTerms = TermsGate.hasAccepted
    @State var translator = Translator()
    @State var editing: EditRequest?
    @State var deleting: Status?
    @State var confirming: ModerationRequest?
    @State var sheet: ShellSheet?
    /// The Focus filter last applied, so it is applied once per change.
    @State private var appliedFocus = FocusFilterState.none
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) var openURLAction
    #if os(iOS)
        @Environment(\.horizontalSizeClass) var horizontalSizeClass
        @Environment(\.verticalSizeClass) var verticalSizeClass
    #endif
    /// Unread conversations, as the messages list last counted them. Read
    /// through `@AppStorage` so the Messages badge moves the moment that list
    /// writes a new count, rather than when this view happens to redraw.
    @AppStorage(AppGroup.unreadConversationsKey, store: AppGroup.defaults)
    var unreadConversations = 0
    #if os(iOS)
        /// Which places a person pinned to the iPad's tab bar, and in what order.
        @AppStorage("aloha.iPad.tabCustomization")
        var tabCustomization = TabViewCustomization()
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
            .environment(\.shellUsesTabBar, !usesSidebar)
            .onChange(of: usesSidebar) { _, toSidebar in handOver(toSidebar: toSidebar) }
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
            .onChange(of: environment.activeSession?.id, initial: true) { previous, current in
                // A link, a notification or a Spotlight result for this
                // account, opened as the switch was made, waits for the reset
                // below rather than being cleared by it.
                let destination = accountSwitch.didShow(current)
                // Another account's pushed screens mean nothing on this one:
                // a thread id from one server is a stranger's post, or none,
                // on the next.
                guard previous != nil, previous != current else { return }
                tabPaths = [:]
                sidebarPaths = [:]
                // For you is Nextcloud Social's; another server has no such feed.
                if selectedSource == .interests,
                    environment.activeSession?.capabilities.isNextcloudSocial != true
                {
                    selectedSource = .home
                }
                if let destination { open(destination) }
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
        let ordered = FeedMode.offered.filter {
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
    func repairFeedSelection(_ modes: [FeedMode]) {
        guard let fallback = modes.first else { return }
        if !modes.contains(selectedMode) { selectedMode = fallback }
        if case .mode(let mode) = selectedTab, !modes.contains(mode) {
            selectedTab = .mode(fallback)
            tabPaths[.mode(mode)] = nil
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

    func unreadNotifications(_ session: AccountSession) -> Int {
        environment.sync.unreadCounts[session.id] ?? 0
    }

    func tabPath(_ tab: TabSelection) -> Binding<[Route]> {
        Binding(get: { tabPaths[tab, default: []] }, set: { tabPaths[tab] = $0 })
    }

    func sidebarPath(_ item: SidebarItem) -> Binding<[Route]> {
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

#if os(iOS)
    private struct WatchTrigger: Equatable {
        var account: UUID?
        var accent: AlohaThemeModifier.ServerTheme?
    }
#endif
