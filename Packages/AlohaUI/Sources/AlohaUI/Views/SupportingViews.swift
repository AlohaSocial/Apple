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
    /// is, what it looks like, whose it is, what it will not do to you, what a
    /// day in it feels like, where else you'll find it, and where to start.
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
                symbol: "server.rack",
                title: Text("Your server, your rules", comment: "Onboarding title"),
                detail: Text(
                    "Aloha Social is a client, not a platform. Sign in to the Nextcloud Social or Mastodon server you already use — your posts, photos and messages stay there.",
                    comment: "Onboarding detail")),
            OnboardingPage(
                symbol: "lock.shield.fill",
                title: Text("Quiet by default", comment: "Onboarding title"),
                detail: Text(
                    "Media behind a content warning stays blurred. Popularity counts can be switched off entirely. Digest notifications wait for the times you pick.",
                    comment: "Onboarding detail")),
            OnboardingPage(
                symbol: "sun.horizon",
                title: Text("A day, not a stream", comment: "Onboarding title"),
                detail: Text(
                    "Open the app and it tells you where you left off. New posts wait above the line until you ask for them.",
                    comment: "Onboarding detail"),
                showsReadingPreview: true),
            OnboardingPage(
                symbol: "applewatch",
                title: Text("Every screen you own", comment: "Onboarding title"),
                detail: Text(
                    "iPhone, iPad, Mac, Apple Watch and Apple TV. One account, and every screen reads the same way.",
                    comment: "Onboarding detail"),
                showsDeviceRow: true),
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
                #if os(iOS)
                    // Every one of these is an iPhone keyboard concern: a Mac
                    // has no keyboard type and no text-content type, and the
                    // suite compiles on one.
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                #endif
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
            // does not exist on every platform, and dots are cheap.
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
                .overlay(alignment: .leading) {
                    // Every page but the first can go back: an introduction is
                    // a tour, and a tour you cannot reverse is a slide show.
                    if page > 0 {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                page -= 1
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.footnote.weight(.semibold))
                                .padding(AlohaMetrics.space3)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(palette.secondaryLabel)
                        .accessibilityLabel(Text("Back", comment: "Onboarding action"))
                    }
                }

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
    /// Where the page also shows the reading experience: where you left off,
    /// and what waits above the line.
    var showsReadingPreview: Bool = false
    /// Where the page also shows the screens the app runs on.
    var showsDeviceRow: Bool = false
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

            if page.showsReadingPreview {
                ReadingPreview()
            }

            if page.showsDeviceRow {
                DeviceRow()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AlohaMetrics.space5)
    }
}

/// The reading experience, as it appears: the line between where you left off
/// and what arrived since.
///
/// This is the app's own idea — a feed that knows when you stopped reading —
/// and a page that *shows* it lands where a sentence about it would not.
private struct ReadingPreview: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics

    var body: some View {
        VStack(spacing: AlohaMetrics.space2) {
            // The new-posts pill: what arrived since, waiting to be asked for.
            HStack(spacing: AlohaMetrics.space1) {
                Image(systemName: "arrow.up")
                    .font(.caption2)
                Text("12 new posts", comment: "Onboarding preview pill")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(palette.onAccent)
            .padding(.horizontal, AlohaMetrics.space3)
            .padding(.vertical, AlohaMetrics.space1)
            .background(palette.accent, in: Capsule())

            // Where you left off.
            VStack(spacing: AlohaMetrics.space2) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(palette.surfaceRaised)
                    .frame(height: 10)
                    .frame(maxWidth: 240, alignment: .leading)
                RoundedRectangle(cornerRadius: 4)
                    .fill(palette.surfaceRaised)
                    .frame(height: 10)
                    .frame(maxWidth: 200, alignment: .leading)
            }
            .padding(AlohaMetrics.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                palette.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
            )

            // The line itself.
            HStack(spacing: AlohaMetrics.space2) {
                Spacer()
                Rectangle()
                    .fill(palette.separator)
                    .frame(width: 56, height: 1)
                Text("You're caught up", comment: "Onboarding preview caption")
                    .font(.caption)
                    .foregroundStyle(palette.tertiaryLabel)
                Rectangle()
                    .fill(palette.separator)
                    .frame(width: 56, height: 1)
                Spacer()
            }

            // What arrived since.
            VStack(spacing: AlohaMetrics.space2) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(palette.surfaceRaised)
                    .frame(height: 10)
                    .frame(maxWidth: 220, alignment: .leading)
                RoundedRectangle(cornerRadius: 4)
                    .fill(palette.surfaceRaised)
                    .frame(height: 10)
                    .frame(maxWidth: 160, alignment: .leading)
            }
            .padding(AlohaMetrics.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                palette.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
            )
        }
        .frame(maxWidth: 320)
        .accessibilityLabel(Text("A preview of a timeline", comment: "Onboarding preview"))
    }
}

/// The screens the app runs on, as the devices themselves.
private struct DeviceRow: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics

    var body: some View {
        HStack(spacing: AlohaMetrics.space4) {
            device("iphone", label: "iPhone")
            device("ipad", label: "iPad")
            device("macbook", label: "Mac")
            device("applewatch", label: "Watch")
            device("appletv", label: "TV")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("iPhone, iPad, Mac, Apple Watch and Apple TV", comment: "Onboarding devices"))
    }

    private func device(_ symbol: String, label: String) -> some View {
        VStack(spacing: AlohaMetrics.space2) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(palette.accent)
                .frame(width: 44, height: 44)
                .unifiedGlass(
                    .subtle,
                    in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
                )
            Text(verbatim: label)
                .font(.caption2)
                .foregroundStyle(palette.secondaryLabel)
        }
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
    @Environment(AppEnvironment.self) private var environment

    private let session: AccountSession
    @Binding private var selection: SidebarItem
    /// Bound for the app shell to write into when a feed source changes; the
    /// sidebar itself no longer reads it, because a source is a property of
    /// the mode's screen rather than of the navigation.
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
        // One list, with the system's own sidebar style, search bar, insets
        // and selection. It used to be a custom search pill floating above a
        // list whose rows carried their own selected background and their own
        // button hover, which is what made it look like a mock-up of a
        // sidebar rather than a sidebar.
        List(selection: optionalSelection) {
            // The shape of Nextcloud Social's own navigation: one primary
            // group of timelines and messages, then Explore, then everything
            // about your own account at the foot.
            Section {
                ForEach(session.visibleModes, id: \.self) { mode in
                    modeRow(mode)
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

            // Everything about your own account, behind your own face, at the
            // foot where Nextcloud Social puts it (`NcAppNavigationSettings`).
            //
            // A section of the same list rather than a block pasted onto the
            // bottom: one scroll, one selection, the system's own insets, and
            // nothing to keep in step with the list's text inset.
            Section {
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        isAccountExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: AlohaMetrics.space3) {
                        AvatarView(account: session.snapshot.asAccount, size: 32)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(session.snapshot.bestDisplayName)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(session.snapshot.qualifiedHandle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: 0)

                        // The system's own affordance for a drawer that opens
                        // and closes, rather than a chevron that rotates.
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
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

                if isAccountExpanded {
                    drawerRow("My profile", symbol: "person.crop.circle", route: myProfile)
                    // Activities is about you rather than about a feed, so it
                    // sits with the rest of what is yours.
                    drawerRow(
                        "Activities", symbol: AlohaSymbol.notifications, route: .notifications)
                    drawerRow(
                        "Follow requests", symbol: "person.badge.clock", route: .followRequests)
                    drawerRow("Liked posts", symbol: AlohaSymbol.favourite, route: .favourites)
                    drawerRow("Bookmarks", symbol: AlohaSymbol.bookmark, route: .bookmarks)
                    if session.capabilities.isNextcloudSocial {
                        drawerRow("Archived posts", symbol: "archivebox", route: .archived)
                        drawerRow("Statistics", symbol: "chart.bar.xaxis", route: .statistics)
                    }
                    drawerRow("Blocking", symbol: "hand.raised", route: .safety)
                    drawerRow("Settings", symbol: AlohaSymbol.settings, route: .settings)

                    // The web is one account per Nextcloud; this app is not,
                    // so switching belongs with everything else that is about
                    // who you are.
                    if environment.sessions.count > 1 {
                        ForEach(environment.sessions.filter { $0.id != session.id }) { other in
                            Button {
                                onSwitchAccount(other.id)
                            } label: {
                                Label {
                                    Text(other.snapshot.bestDisplayName)
                                } icon: {
                                    Image(systemName: "arrow.left.arrow.right")
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                Text(
                                    "Switch to \(other.snapshot.qualifiedHandle)",
                                    comment: "Account switcher action")
                            )
                        }
                    }

                    Button {
                        onAddAccount()
                    } label: {
                        Label {
                            Text("Add account…", comment: "Account switcher action")
                        } icon: {
                            Image(systemName: "person.badge.plus")
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Add account", comment: "Account switcher action"))
                }
            }
        }
        .listStyle(.sidebar)
        // The system's own search bar, in the sidebar's slot: it widens the
        // navigation on iPad the way the system apps do, for free.
        .searchable(
            text: $searchText,
            placement: .sidebar,
            prompt: Text("Search", comment: "Sidebar search field")
        )
        .onSubmit(of: .search, submitSearch)
        // The sidebar is the one column that should not scroll under the
        // content: it is navigation, and a navigation item that moves while
        // you are reading is a moving target.
        .scrollContentBackground(.hidden)
        .navigationTitle(Text("Aloha Social", comment: "App name"))
    }

    /// A mode row: the symbol in its own tile, filled while selected. A tile
    /// gives every row the same weight, which a bare symbol never does when
    /// one icon is a house and the next is a stack.
    /// A mode row: the same Label the fixed destinations use, with the tag
    /// that makes the system draw its own selection.
    ///
    /// It used to be a Button carrying its own icon tile and its own selected
    /// background, inside a list that already selects — so a selected row had
    /// two highlights drawn on it, one by the system and one by hand, and the
    /// row answered the pointer with the hover of a button rather than the
    /// highlight of a row.
    private func modeRow(_ mode: FeedMode) -> some View {
        let isSelected = selection == .mode(mode)
        return Label {
            Text(title(for: mode))
        } icon: {
            Image(systemName: isSelected ? mode.selectedSymbolName : mode.symbolName)
        }
        .tag(SidebarItem.mode(mode))
        .accessibilityLabel(Text(title(for: mode)))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// A drawer row that closes the section behind it — the web's drawer does
    /// the same rather than staying open over the page it just opened.
    private func drawerRow(
        _ title: String.LocalizationValue, symbol: String, route: Route
    ) -> some View {
        Button {
            selection = .route(route)
            withAnimation(.easeOut(duration: 0.2)) { isAccountExpanded = false }
        } label: {
            row(title, symbol: symbol, route: route, comment: "Sidebar item")
        }
        .buttonStyle(.plain)
    }

    /// Submitting the system's search bar navigates to the results, rather
    /// than leaving the typed query where the system put it.
    private func submitSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        selection = .route(.search(query: query))
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
