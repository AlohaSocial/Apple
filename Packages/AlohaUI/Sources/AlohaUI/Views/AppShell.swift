// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// The root. A tab bar on iPhone, a split view everywhere else.
public struct AppShell: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// A tab bar selection that can be a mode *or* the messages tab.
    /// Tagging the extra tab with `FeedMode.home` made the two collide.
    private enum TabSelection: Hashable {
        case mode(FeedMode)
        case messages
    }

    @State private var selectedTab: TabSelection = .mode(.home)
    @State private var selectedMode: FeedMode = .home
    @State private var sidebarItem: SidebarItem = .mode(.home)
    @State private var selectedSource: TimelineSource = .home
    @State private var path: [Route] = []
    @State private var isPresentingSignIn = false
    @State private var composing: ComposerPresentation?
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
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    /// The theme wraps everything the shell can put on screen, including its
    /// presentations. It cannot be one more link in the chain below.
    ///
    /// `alohaTheme` works by writing into the environment, and a `.sheet`
    /// attached *above* that write does not inherit it — the presentation is a
    /// sibling of the environment modifier, not a descendant. With the theme
    /// applied mid-chain, every sheet the shell owns — composer, sign-in,
    /// report, edit, and the media viewer — fell back to the `@Entry` default
    /// in `AlohaDesign`, which is Warm Light. The app ran in Black and the
    /// composer opened cream.
    ///
    /// Nesting rather than appending is what makes that unrepeatable: a
    /// `.sheet` added to `content` later is inside the wrap by construction,
    /// wherever in the chain it lands.
    public var body: some View {
        content
            .alohaTheme(
                environment.theme, metrics: environment.metrics, accent: environment.serverAccent
            )
    }

    private var content: some View {
        root
            .overlay {
                if isCelebrating { ConfettiView(isFalling: isCelebrating) }
            }
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
            .onChange(of: scenePhase) { _, phase in
                // A socket closes on background immediately; BGAppRefreshTask
                // takes over from there (docs/08 §6).
                environment.sync.setForeground(phase == .active)
            }
            .onOpenURL { url in handle(url) }
            .onReceive(NotificationCenter.default.publisher(for: .alohaOpenRoute)) { note in
                // Where Handoff arrives.
                if let route = note.userInfo?["route"] as? Route { open(route) }
            }
    }

    @ViewBuilder
    private var root: some View {
        if environment.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !hasAcceptedTerms {
            TermsGate(
                onAccept: { hasAcceptedTerms = true },
                onDecline: { hasAcceptedTerms = false })
        } else if let session = environment.activeSession {
            shell(session)
                // Switching accounts has to change view identity: every
                // timeline holds its model in `@State`, and without this the
                // previous account's posts stay on screen and its client keeps
                // serving the actions (docs/03 §6).
                .id(session.id)
        } else {
            WelcomeView { isPresentingSignIn = true }
        }
    }

    private func start() async {
        await environment.load()
        #if DEBUG
            if MockMode.isEnabled {
                await MockMode.seedIfNeeded(environment)
                hasAcceptedTerms = !MockMode.startsSignedOut
            }
        #endif
        environment.sync.attach(to: environment)
        environment.sync.start()
        environment.notifier.registerCategories()
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
        // An intent that opened the app left its destination behind.
        if let pending = IntentNavigation.take() { open(pending) }
    }

    func open(_ route: Route) {
        if case .timeline(let key) = route {
            selectedMode = key.mode
            selectedTab = .mode(key.mode)
            sidebarItem = .mode(key.mode)
            selectedSource = key.source
            path = []
        } else if !usesSidebar, route == .conversations {
            // On a phone direct messages are a tab, not a push.
            selectedTab = .messages
            path = []
        } else if usesSidebar, SidebarItem.sidebarRoutes.contains(route) {
            // On a split view these are sidebar rows, not pushes.
            sidebarItem = .route(route)
            path = []
        } else {
            path.append(route)
        }
    }

    private var usesSidebar: Bool {
        #if os(iOS)
            sizeClass != .compact
        #else
            true
        #endif
    }
    @ViewBuilder
    private func shell(_ session: AccountSession) -> some View {
        #if os(iOS)
            if sizeClass == .compact {
                tabShell(session)
            } else {
                splitShell(session)
            }
        #else
            splitShell(session)
        #endif
    }

    // MARK: - iPhone

    #if os(iOS)
        private func tabShell(_ session: AccountSession) -> some View {
            TabView(selection: $selectedTab) {
                ForEach(session.visibleModes) { mode in
                    Tab(value: TabSelection.mode(mode)) {
                        NavigationStack(path: $path) {
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
                    NavigationStack(path: $path) {
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
            }
            .onChange(of: selectedTab) { _, tab in
                if case .mode(let mode) = tab { selectedMode = mode }
            }
            // The one way to write something: a button beside the tab bar, not
            // a toolbar icon and not a floating circle. A toolbar puts it four
            // taps from the content and a floating button duplicates the tab
            // bar's thumb zone — the accessory slot is where Apple puts the
            // primary action of a tab app.
            .tabViewBottomAccessory {
                composeAccessory
            }
        }
    #endif

    /// New post in the tab bar's accessory slot: labelled, always on screen,
    /// out of the way of the thumb.
    @available(iOS 18.0, tvOS 18.0, visionOS 2.0, *)
    private var composeAccessory: some View {
        Button {
            composing = ComposerPresentation()
        } label: {
            Label {
                Text("New post", comment: "Compose accessory")
            } icon: {
                Image(systemName: AlohaSymbol.compose)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .keyboardShortcut("n", modifiers: .command)
        .accessibilityLabel(Text("New post", comment: "Compose button"))
        .tint(environment.activeSession.map { session in
            environment.theme.palette(for: .light).accent
        } ?? .accentColor)
    }

    // MARK: - iPad, Mac, Vision

    private func splitShell(_ session: AccountSession) -> some View {
        NavigationSplitView {
            SidebarView(
                session: session,
                selection: $sidebarItem,
                selectedSource: $selectedSource,
                onAddAccount: { isPresentingSignIn = true },
                onSwitchAccount: { environment.setActiveAccount($0) })
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    switch sidebarItem {
                    case .mode(let mode):
                        modeRoot(mode, session: session)
                    case .route(let route):
                        destination(route, session: session)
                    }
                }
                .navigationDestination(for: Route.self) { destination($0, session: session) }
            }
        }
        .onChange(of: sidebarItem) { _, item in
            // A new root; whatever was pushed belonged to the old one.
            path = []
            if case .mode(let mode) = item { selectedMode = mode }
        }
        .toolbar {
            ToolbarItem {
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
            }
        }
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
                .navigationTitle(modeTitle(mode)),
                session: session)

        case .news:
            timelineChrome(
                NewsModeView(session: session, source: selectedSource) {
                    handle($0, session: session)
                }
                .navigationTitle(modeTitle(mode)),
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
                .onAppear { environment.sync.noteTimelineVisible(for: session.id) },
                session: session)
        }
    }

    /// What every timeline screen wears: the account menu on a phone, and the
    /// source toggle at its foot.
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
            .modifier(ScrollRevealedTimelineSource(source: $selectedSource))
            #if os(iOS)
                .toolbar {
                    // Only on the phone: the split shell carries both of these
                    // in the sidebar — the account drawer at its foot, and a
                    // search field at its head.
                    if sizeClass == .compact {
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
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                composing = ComposerPresentation()
                            } label: {
                                Image(systemName: AlohaSymbol.compose)
                            }
                            .keyboardShortcut("n", modifiers: .command)
                            .accessibilityLabel(Text("New post", comment: "Toolbar action"))
                        }
                    }
                }
            #endif
    }

    @ViewBuilder
    private func destination(_ route: Route, session: AccountSession) -> some View {
        switch route {
        case .thread(let statusID):
            ThreadView(statusID: statusID, session: session) { handle($0, session: session) }
        case .profile(let accountID):
            ProfileView(accountID: accountID, session: session) { handle($0, session: session) }
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
        case .settings:
            SettingsView(onAddAccount: { isPresentingSignIn = true })
        case .explore:
            ExploreView(session: session) { handle($0, session: session) }
        case .search(let query):
            SearchView(session: session, initialQuery: query) { handle($0, session: session) }
        case .lists:
            ListsView(session: session)
        case .filters:
            FiltersView(session: session)
        case .safety:
            SafetyListsView(session: session)
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
        case .subscriptions:
            SubscriptionsView(session: session)
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
            path.append(.thread(statusID: status.displayed.id))
        case .watch(let status):
            path.append(.video(statusID: status.displayed.id))
        case .openProfile(let account):
            path.append(.profile(accountID: account.id))
        case .openMedia(let status, let index):
            mediaPresentation = MediaPresentation(
                statusID: status.id, attachments: status.mediaAttachments, index: index)
        case .reply(let status):
            composing = ComposerPresentation(replyTo: status.displayed)
        case .followLink(let link):
            switch link {
            case .mention(let accountID, let acct, _):
                path.append(accountID.map { Route.profile(accountID: $0) } ?? .handle(acct))
            case .hashtag(let name, _):
                path.append(.hashtag(name))
            case .web(let url):
                #if canImport(UIKit)
                    UIApplication.shared.open(url)
                #endif
            }
        case .openCard(let card):
            if let url = card.url {
                #if canImport(UIKit)
                    UIApplication.shared.open(url)
                #endif
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

    private func share(_ status: Status) {
        guard let url = status.displayed.url else { return }
        #if canImport(UIKit)
            let activity = UIActivityViewController(
                activityItems: [url], applicationActivities: nil)
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }?
                .keyWindow?.rootViewController?
                .present(activity, animated: true)
        #elseif canImport(AppKit)
            let picker = NSSharingServicePicker(items: [url])
            if let view = NSApplication.shared.keyWindow?.contentView {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
        #endif
    }

    private func handle(_ url: URL) {
        // The browser fallback for sign-in comes back this way, and it is not
        // a navigation destination.
        if WebAuthenticator.shared.deliver(url) { return }

        guard let route = RouteResolver.route(for: url) else { return }
        if case .timeline(let key) = route {
            selectedMode = key.mode
            selectedSource = key.source
            path = []
        } else {
            path.append(route)
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

extension View {
    /// `fullScreenCover` does not exist on macOS; a sheet is the right
    /// equivalent there.
    @ViewBuilder
    func fullScreenCoverIfAvailable<Item: Identifiable, Content: View>(
        item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(macOS)
            sheet(item: item, content: content)
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
