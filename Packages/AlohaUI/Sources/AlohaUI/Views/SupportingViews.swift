// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

public struct WelcomeView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics

    /// Called with what the last page's field holds, so the sign-in screen
    /// opens with the address already in it rather than asking again.
    private let onAddAccount: (String?) -> Void

    public init(onAddAccount: @escaping (String?) -> Void = { _ in }) {
        self.onAddAccount = onAddAccount
    }

    /// The introduction, in the order a person can agree with it: what this
    /// is, what it looks like, what it will not do to you, and where to start.
    /// The last page is the beginning itself, not a button that begins.
    private var pages: [OnboardingPage] {
        [
            OnboardingPage(
                symbol: "bubble.left.and.text.bubble.right",
                title: Text("Welcome to Aloha Social", comment: "Onboarding title"),
                detail: Text(
                    "A calmer client for the social web. Read, post, photograph and message — on your own server, in your own time.",
                    comment: "Onboarding detail"),
                isHero: true),
            OnboardingPage(
                symbol: "square.stack.3d.up.fill",
                title: Text("Six feeds, each its own screen", comment: "Onboarding title"),
                detail: Text(
                    "Home is everything. Photos is a grid of pictures. Video remembers where you got to. Shorts is full screen.",
                    comment: "Onboarding detail"),
                showsModeTour: true),
            OnboardingPage(
                symbol: "lock.shield.fill",
                title: Text("Quiet by default", comment: "Onboarding title"),
                detail: Text(
                    "Media behind a content warning stays blurred. Popularity counts can be switched off entirely. Digest notifications wait for the times you pick.",
                    comment: "Onboarding detail")),
        ]
    }

    @State private var page = 0
    /// The last page's field, seeded into the sign-in flow so the address is
    /// typed once, here, where the app already has your attention.
    @State private var serverAddress = ""
    @FocusState private var isAddressFocused: Bool

    /// The tour's pages plus the page you sign in on.
    private var pageCount: Int { pages.count + 1 }

    public var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, content in
                    OnboardingPageView(page: content)
                        .tag(index)
                }

                signInPage
                    .tag(pages.count)
            }
            #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
            #endif

            footer
                .padding(.horizontal, AlohaMetrics.space5)
                .padding(.bottom, AlohaMetrics.space5)
        }
        .background(palette.background.ignoresSafeArea())
    }

    /// The last page is the beginning: the server address, here, rather than a
    /// button that opens somewhere else and asks again.
    private var signInPage: some View {
        VStack(spacing: AlohaMetrics.space4) {
            Spacer(minLength: 0)

            Text("Where do you socialize?", comment: "Onboarding sign-in title")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text(
                "Your server's address — for example aloha.example.org. You sign in on your server; Aloha Social only connects.",
                comment: "Onboarding sign-in detail"
            )
            .font(.subheadline)
            .foregroundStyle(palette.secondaryLabel)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 400)

            VStack(spacing: AlohaMetrics.space2) {
                TextField(
                    text: $serverAddress,
                    prompt: Text("cloud.example.com", comment: "Server address placeholder")
                ) {
                    Label {
                        Text("Server", comment: "Server address field")
                    } icon: {
                        Image(systemName: "server.rack")
                    }
                }
                .textContentType(.URL)
                .keyboardType(.URL)
                #if os(iOS)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                #endif
                .submitLabel(.go)
                .focused($isAddressFocused)
                .onSubmit(start)
                .disabled(serverAddress.trimmingCharacters(in: .whitespaces).isEmpty)

                Button(action: start) {
                    Text("Continue", comment: "Onboarding sign-in action")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.alohaProminent)
                .disabled(serverAddress.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AlohaMetrics.space5)
    }

    /// Hands what was typed to the sign-in flow, so the address is typed once
    /// here rather than again on the next screen.
    private func start() {
        let typed = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        onAddAccount(typed.isEmpty ? nil : typed)
    }

    private var footer: some View {
        VStack(spacing: AlohaMetrics.space3) {
            // Owned rather than `.tabViewStyle(.page)`'s indicator: that style
            // does not exist on every platform, and four dots are cheap.
            HStack(spacing: AlohaMetrics.space2) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == page ? palette.accent : palette.separator)
                        .frame(width: index == page ? 9 : 6, height: index == page ? 9 : 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: page)
                }
            }
            .accessibilityHidden(true)

            if page < pageCount - 1 {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { page += 1 }
                } label: {
                    Text("Continue", comment: "Onboarding action")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.alohaProminent)

                Button {
                    // Straight to the page you sign in on, where the address
                    // already is.
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        page = pageCount - 1
                        isAddressFocused = true
                    }
                } label: {
                    Text("Skip", comment: "Onboarding action")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(palette.secondaryLabel)
            } else {
                Text(
                    "Don't know your address? Your server's website has it, or ask whoever runs it.",
                    comment: "Onboarding footnote"
                )
                .font(.caption)
                .foregroundStyle(palette.tertiaryLabel)
                .multilineTextAlignment(.center)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: page)
    }
}

/// One promise, as a page of the introduction.
private struct OnboardingPage: Identifiable {
    let id = UUID()
    let symbol: String
    let title: Text
    let detail: Text
    /// Where the page also shows the six feeds as tiles: people believe a
    /// picture of the thing they will use more than a paragraph about it.
    var showsModeTour: Bool = false
    /// The hero page carries the app's own lockup rather than a symbol in a
    /// glass tile — an app's first screen should look like that app.
    var isHero: Bool = false
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics

    var body: some View {
        VStack(spacing: AlohaMetrics.space5) {
            Spacer(minLength: 0)

            if page.isHero {
                // The app's own mark and wordmark: the first screen a person
                // sees should look like the app they are about to use.
                AlohaLogo()
            } else {
                Image(systemName: page.symbol)
                    .font(.system(size: 62))
                    .foregroundStyle(palette.accent)
                    .frame(width: 148, height: 148)
                    .unifiedGlass(
                        .regular,
                        in: RoundedRectangle(
                            cornerRadius: AlohaMetrics.cornerLarge * 2, style: .continuous)
                    )
                    .accessibilityHidden(true)
            }

            VStack(spacing: AlohaMetrics.space3) {
                if page.isHero {
                    page.detail
                        .font(.body)
                        .foregroundStyle(palette.secondaryLabel)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                } else {
                    page.title
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                    page.detail
                        .font(.body)
                        .foregroundStyle(palette.secondaryLabel)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }

            if page.showsModeTour {
                // The six feeds as they actually appear, with the same symbols
                // the sidebar uses — an introduction that shows the app rather
                // than describing it.
                ModeTour()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AlohaMetrics.space5)
    }
}

/// The six feeds, as tiles, on the introduction's second page.
///
/// These are the same symbols and names the sidebar and tab bar carry, so
/// nothing here is invented for the tour: what a person sees is what they get.
private struct ModeTour: View {
    @Environment(\.alohaPalette) private var palette

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: AlohaMetrics.space2)],
            spacing: AlohaMetrics.space2
        ) {
            ForEach(FeedMode.allCases) { mode in
                VStack(spacing: AlohaMetrics.space2) {
                    Image(systemName: mode.symbolName)
                        .font(.title3)
                        .foregroundStyle(mode == .home ? palette.accent : palette.secondaryLabel)
                        .frame(width: 44, height: 44)
                        .unifiedGlass(
                            .subtle,
                            in: RoundedRectangle(
                                cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
                        )
                    Text(modeTitle(mode))
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: 420)
        .accessibilityLabel(
            Text(
                "The six feeds: Home, Photos, Video, Shorts, News and Audio.",
                comment: "Mode tour")
        )
    }

    private func modeTitle(_ mode: FeedMode) -> String {
        switch mode {
        case .home: String(localized: "Home", comment: "Feed mode")
        case .photos: String(localized: "Photos", comment: "Feed mode")
        case .video: String(localized: "Video", comment: "Feed mode")
        case .shorts: String(localized: "Shorts", comment: "Feed mode")
        case .news: String(localized: "News", comment: "Feed mode")
        case .audio: String(localized: "Audio", comment: "Feed mode")
        }
    }
}

/// What the sidebar can select: a mode, or one of the fixed destinations.
///
/// The split view's detail column shows whichever is selected; a value-based
/// `NavigationLink` in the sidebar has no stack of its own to push onto, which
/// is how every non-mode item came to do nothing.
public enum SidebarItem: Hashable, Sendable {
    case mode(FeedMode)
    case route(Route)

    /// The destinations that live in the sidebar rather than being pushed.
    public static let sidebarRoutes: [Route] = [
        .notifications, .conversations, .explore, .search(query: nil), .lists,
        .interests, .subscriptions, .collections(accountID: nil),
        .followRequests, .favourites, .bookmarks, .archived, .statistics, .safety, .settings,
    ]
}

public struct SidebarView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(AppEnvironment.self) private var environment

    private let session: AccountSession
    @Binding private var selection: SidebarItem
    @Binding private var selectedSource: TimelineSource
    /// Collapsed until asked for, as the web is.
    @State private var isAccountExpanded = false
    @State private var searchText = ""

    private let onAddAccount: () -> Void
    private let onSwitchAccount: (UUID) -> Void

    public init(
        session: AccountSession,
        selection: Binding<SidebarItem>,
        selectedSource: Binding<TimelineSource>,
        onAddAccount: @escaping () -> Void,
        onSwitchAccount: @escaping (UUID) -> Void
    ) {
        self.session = session
        _selection = selection
        _selectedSource = selectedSource
        self.onAddAccount = onAddAccount
        self.onSwitchAccount = onSwitchAccount
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchField
            sidebarList
        }
        .background(palette.background)
        .navigationTitle(Text("Aloha Social", comment: "App name"))
        .safeAreaInset(edge: .bottom) { accountDrawer }
    }

    /// The web puts a search bar at the top of its navigation, above the
    /// timelines, rather than a magnifier in the toolbar.
    private var searchField: some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.search)
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)
            TextField(
                text: $searchText,
                prompt: Text("Search", comment: "Sidebar search field")
            ) {
                Text("Search", comment: "Sidebar search field")
            }
            .textFieldStyle(.plain)
            .font(.subheadline)
            .onSubmit(submitSearch)
            #if os(iOS)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            #endif

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.tertiaryLabel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search", comment: "Sidebar search field"))
            }
        }
        .padding(.horizontal, AlohaMetrics.space3)
        .padding(.vertical, AlohaMetrics.space2)
        // Glass, the way a field in a sidebar is drawn: a material with a
        // hairline edge, not a flat fill that ignores what is behind it.
        .unifiedGlass(
            .subtle,
            in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
        )
        .padding(.horizontal, AlohaMetrics.space3)
        .padding(.top, AlohaMetrics.space2)
        .padding(.bottom, AlohaMetrics.space1)
    }

    private func submitSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        selection = .route(.search(query: query))
    }

    private var sidebarList: some View {
        // iOS requires an optional (or Set) selection binding; macOS accepts a
        // plain one. Bridging here keeps the caller's binding non-optional.
        // The shape of Nextcloud Social's own navigation: one primary group of
        // timelines, then Explore, then everything about your own account.
        //
        // `.sidebar` is the style that makes the list *be* a sidebar: the
        // system's own insets, section headings and — the point — the selected
        // row's highlight. Drawing our own on top of the default style is what
        // made this look like a List wearing a sidebar costume.
        List(selection: optionalSelection) {
            Section {
                ForEach(session.visibleModes, id: \.self) { mode in
                    modeRow(mode)
                        .tag(SidebarItem.mode(mode))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                row(
                    "Direct messages",
                    symbol: selectedRoute == .conversations
                        ? "envelope.fill" : AlohaSymbol.envelope, route: .conversations,
                    comment: "Sidebar item")
                row(
                    "Discover", symbol: selectedRoute == .explore ? "safari.fill" : "safari",
                    route: .explore,
                    comment: "Sidebar item")
            }

            Section {
                row(
                    "Your lists",
                    symbol: selectedRoute == .lists
                        ? "list.bullet.rectangle.fill" : "list.bullet.rectangle", route: .lists,
                    comment: "Sidebar item")
                if session.capabilities.isNextcloudSocial {
                    row(
                        "My interests", symbol: "sparkles", route: .interests,
                        comment: "Sidebar item")
                    row(
                        "Subscriptions", symbol: "dot.radiowaves.up.forward",
                        route: .subscriptions, comment: "Sidebar item")
                }
                if session.capabilities.collections {
                    row(
                        "Albums", symbol: "rectangle.stack", route: .collections(accountID: nil),
                        comment: "Sidebar item")
                }
            } header: {
                Text("Explore", comment: "Sidebar section")
            }
        }
        .listStyle(.sidebar)
        // The sidebar is the one column that should not scroll under the
        // content: it is navigation, and a navigation item that moves while
        // you are reading is a moving target.
        .scrollContentBackground(.hidden)
    }

    /// A mode row: the symbol in its own tile, filled while selected. A tile
    /// gives every row the same weight, which a bare symbol never does when
    /// one icon is a house and the next is a stack.
    private func modeRow(_ mode: FeedMode) -> some View {
        let isSelected = selection == .mode(mode)
        return Button {
            selection = .mode(mode)
        } label: {
            HStack(spacing: AlohaMetrics.space3) {
                Image(systemName: isSelected ? mode.selectedSymbolName : mode.symbolName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isSelected ? palette.accent : palette.secondaryLabel)
                    .frame(width: 28, height: 28)
                    .background(
                        isSelected ? palette.accent.opacity(0.14) : palette.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                Text(title(for: mode))
                    .fontWeight(isSelected ? .semibold : .regular)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title(for: mode)))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Everything about your own account, behind your own face.
    ///
    /// Nextcloud Social puts this at the foot of its navigation as
    /// `NcAppNavigationSettings`: the avatar and display name are the toggle,
    /// the drawer is collapsed until you click it, and it holds the pages that
    /// are about you rather than about a timeline.
    ///
    /// Everything in the drawer is native: sidebar rows, the system's
    /// borderless button style, `Label` with `.titleAndIcon`, and insets that
    /// match the list above it. The hand-rolled selection pill it used to draw
    /// is gone — a selected sidebar row takes the accent on its own label, the
    /// way Mail and Notes highlight theirs.
    private var accountDrawer: some View {
        // One container for every glass shape in the drawer, the way Apple's
        // Landmarks sample groups its badges and toggle: neighbouring shapes
        // blend rather than each blurring alone, and the toggle can morph into
        // the drawer it opens.
        GlassEffectContainer(spacing: AlohaMetrics.space3) {
            VStack(spacing: 0) {
                Divider()
                    .padding(.leading, AlohaMetrics.space3)

                if isAccountExpanded {
                    // Sized to its rows, and only scrolls when there are more
                    // than fit: a ScrollView on its own claims all the height
                    // offered.
                    ViewThatFits(in: .vertical) {
                        drawerContent
                        ScrollView { drawerContent }
                    }
                    .glassEffectID("drawer", in: drawerNamespace)
                    .glassEffectTransition(.materialize)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                accountToggle
                    .glassEffectID("toggle", in: drawerNamespace)
            }
        }
        .background(palette.surface)
    }

    /// The namespace that lets the toggle morph into the drawer it opens,
    /// rather than two unrelated blurs appearing and disappearing.
    @Namespace private var drawerNamespace

    private var drawerContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            drawerRow("My profile", symbol: "person.crop.circle", route: myProfile)
            // Activities is about you rather than about a feed, so it sits with
            // the rest of what is yours rather than among the timelines.
            drawerRow("Activities", symbol: AlohaSymbol.notifications, route: .notifications)
            drawerRow("Follow requests", symbol: "person.badge.clock", route: .followRequests)
            drawerRow("Liked posts", symbol: AlohaSymbol.favourite, route: .favourites)
            drawerRow("Bookmarks", symbol: AlohaSymbol.bookmark, route: .bookmarks)
            if session.capabilities.isNextcloudSocial {
                drawerRow("Archived posts", symbol: "archivebox", route: .archived)
                drawerRow("Statistics", symbol: "chart.bar.xaxis", route: .statistics)
            }
            drawerRow("Blocking", symbol: "hand.raised", route: .safety)
            drawerRow("Settings", symbol: AlohaSymbol.settings, route: .settings)

            // The web is one account per Nextcloud; this app is not, so
            // switching belongs with everything else that is about who you are.
            if environment.sessions.count > 1 {
                insetDivider
                ForEach(environment.sessions.filter { $0.id != session.id }) { other in
                    drawerButton(
                        other.snapshot.bestDisplayName,
                        symbol: "arrow.left.arrow.right",
                        accessibilityLabel: Text(
                            "Switch to \(other.snapshot.qualifiedHandle)",
                            comment: "Account switcher action")
                    ) {
                        onSwitchAccount(other.id)
                    }
                }
            }

            insetDivider
            drawerButton(
                String(localized: "Add account…", comment: "Account switcher action"),
                symbol: "person.badge.plus",
                accessibilityLabel: Text("Add account", comment: "Account switcher action"),
                action: onAddAccount)
        }
        .padding(.vertical, AlohaMetrics.space2)
    }

    /// A divider that starts where the text starts, the way a grouped list
    /// separates its sections rather than running a rule under the whole row.
    private var insetDivider: some View {
        Divider()
            .padding(.leading, AlohaMetrics.space3 + AlohaMetrics.space3 + 20)
            .padding(.vertical, AlohaMetrics.space1)
    }

    private var accountToggle: some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                isAccountExpanded.toggle()
            }
        } label: {
            HStack(spacing: AlohaMetrics.space3) {
                AvatarView(account: session.snapshot.asAccount, size: 32)

                VStack(alignment: .leading, spacing: 0) {
                    Text(session.snapshot.bestDisplayName)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(palette.label)
                        .lineLimit(1)
                    Text(session.snapshot.qualifiedHandle)
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                // The system's own affordance for a drawer that opens and
                // closes, rather than a chevron that rotates by hand.
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(palette.tertiaryLabel)
            }
            .padding(AlohaMetrics.space3)
            .contentShape(Rectangle())
            // The toggle's own glass, so it has a material to morph from and
            // to: an id without a shape is an id with nothing to match.
            .glassEffect(.regular.interactive())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                "\(session.snapshot.bestDisplayName), account menu",
                comment: "Accessibility label for the account drawer toggle")
        )
        .accessibilityValue(
            isAccountExpanded
                ? Text("Expanded", comment: "Accessibility state")
                : Text("Collapsed", comment: "Accessibility state")
        )
        .accessibilityAddTraits(.isButton)
    }

    /// A drawer row that selects a destination, closing the drawer behind it —
    /// the web's drawer does the same rather than staying open over the page
    /// it just opened.
    private func drawerRow(
        _ title: String.LocalizationValue, symbol: String, route: Route
    ) -> some View {
        drawerButton(
            String(localized: title, comment: "Sidebar item"), symbol: symbol,
            accessibilityLabel: Text(String(localized: title, comment: "Sidebar item")),
            isSelected: selection == .route(route)
        ) {
            selection = .route(route)
            withAnimation(.easeOut(duration: 0.2)) { isAccountExpanded = false }
        }
    }

    private func drawerButton(
        _ title: String, symbol: String, accessibilityLabel: Text,
        isSelected: Bool = false, action: @escaping () -> Void
    ) -> some View {
        // Native sidebar rows: a label, the borderless style, and a selection
        // that tints the row's own content instead of a drawn-on pill.
        Button(action: action) {
            Label {
                Text(title)
                    .foregroundStyle(isSelected ? palette.accent : palette.label)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(isSelected ? palette.accent : palette.secondaryLabel)
            }
            .labelStyle(.titleAndIcon)
            .font(.subheadline)
            .padding(.horizontal, AlohaMetrics.space3)
            .padding(.vertical, AlohaMetrics.space2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? palette.accent.opacity(0.12) : .clear,
                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
            )
            .padding(.horizontal, AlohaMetrics.space2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        // Interactive glass: a row answers the pointer and the touch, so its
        // material responds the way the system's own controls do.
        .selectedGlass(isSelected, tint: palette.accent)
    }

    private var myProfile: Route {
        .profile(accountID: session.snapshot.serverAccountID)
    }

    /// One row, so the list reads as a list rather than as forty lines of
    /// `Label`.
    @ViewBuilder
    private func row(
        _ title: String.LocalizationValue, symbol: String, route: Route, comment: StaticString
    ) -> some View {
        Label {
            Text(String(localized: title, comment: comment))
        } icon: {
            Image(systemName: symbol)
        }
        .tag(SidebarItem.route(route))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var optionalSelection: Binding<SidebarItem?> {
        Binding(
            get: { selection },
            set: { if let value = $0 { selection = value } })
    }

    /// The selected destination, if it is one of the fixed ones — so its
    /// symbol can take the filled spelling while it is on screen.
    private var selectedRoute: Route? {
        if case .route(let route) = selection { return route }
        return nil
    }

    private func title(for mode: FeedMode) -> String {
        switch mode {
        case .home: String(localized: "My Feed", comment: "Mode title")
        case .photos: String(localized: "Photos", comment: "Mode title")
        case .video: String(localized: "Videos", comment: "Mode title")
        case .shorts: String(localized: "Shorts", comment: "Mode title")
        case .news: String(localized: "News", comment: "Mode title")
        case .audio: String(localized: "Audio", comment: "Mode title")
        }
    }
}
