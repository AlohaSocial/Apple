// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

public struct WelcomeView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Called with what the last page's field holds, so the sign-in screen
    /// opens with the address already in it rather than asking again.
    private let onAddAccount: (String?) -> Void

    public init(onAddAccount: @escaping (String?) -> Void = { _ in }) {
        self.onAddAccount = onAddAccount
    }

    /// Three short pages introduce the app before the server address.
    /// Optional feature details belong in the app rather than delaying sign-in.
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
            Group {
                if page < pages.count {
                    OnboardingPageView(page: pages[page])
                } else {
                    signInPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(page)
            .transition(.opacity)

            footer
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AlohaMetrics.space5)
                .padding(.bottom, AlohaMetrics.space5)
        }
        .background(palette.background.ignoresSafeArea())
    }

    /// The last page is the beginning: the server address, here, rather than a
    /// button that opens somewhere else and asks again.
    private var signInPage: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: AlohaMetrics.space4) {
                    VStack(spacing: AlohaMetrics.space2) {
                        Text("Where do you socialize?", comment: "Onboarding sign-in title")
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)

                        Text(
                            "Your server's address — for example aloha.example.org. You sign in on your server; Aloha Social only connects.",
                            comment: "Onboarding sign-in detail"
                        )
                        .font(.body)
                        .foregroundStyle(palette.secondaryLabel)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    }

                    TextField(
                        text: $serverAddress,
                        prompt: Text("cloud.example.com", comment: "Server address placeholder")
                    ) {
                        Text("Server", comment: "Server address field")
                    }
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
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
                    // The field is never disabled: a field that refuses the first
                    // character because there is not yet a second is a field that
                    // cannot be used at all. Only the action it feeds waits.
                    .frame(maxWidth: 380)

                    Button(action: start) {
                        Text("Continue", comment: "Onboarding sign-in action")
                            .frame(maxWidth: .infinity)
                    }
                    .alohaGlassProminentButtonStyle()
                    .controlSize(.large)
                    // Return continues on a hardware keyboard: on the Mac the
                    // introduction is a window, and a primary action without a
                    // default shortcut is one a keyboard cannot reach.
                    .keyboardShortcut(.defaultAction)
                    .disabled(serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .frame(maxWidth: 380)

                    Text(
                        "Don't know your address? Your server's website has it, or ask whoever runs it.",
                        comment: "Onboarding footnote"
                    )
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                    .multilineTextAlignment(.center)

                }
                .padding(.horizontal, AlohaMetrics.space5)
                .padding(.vertical, AlohaMetrics.space4)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            // Unavailable on visionOS, where there is no keyboard over the
            // content to dismiss.
            #if !os(visionOS)
                .scrollDismissesKeyboard(.interactively)
            #endif
            .accessibilityIdentifier("welcome-sign-in-content")
        }
    }

    /// Hands what was typed to the sign-in flow, so the address is typed once
    /// here rather than again on the next screen.
    private func start() {
        let typed = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        isAddressFocused = false
        onAddAccount(typed)
    }

    /// Dots, then the action, then the way back and the way out.
    private var footer: some View {
        VStack(spacing: AlohaMetrics.space3) {
            // Owned rather than `.tabViewStyle(.page)`'s indicator: that style
            // does not exist on every platform, and dots are cheap.
            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == page ? palette.accent : palette.tertiaryLabel.opacity(0.35))
                        .frame(width: 7, height: 7)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: page)
                }
            }
            .accessibilityHidden(true)

            if page < pageCount - 1 {
                Button {
                    withAnimation(
                        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)
                    ) { page += 1 }
                } label: {
                    Text("Continue", comment: "Onboarding action")
                        .frame(maxWidth: .infinity)
                }
                .alohaGlassProminentButtonStyle()
                .controlSize(.large)
                // The tour is keyboard-navigable on iPad and Mac: Return
                // advances, so the introduction never traps keyboard users.
                .keyboardShortcut(.defaultAction)

                HStack {
                    if page > 0 {
                        // Every page but the first can go back: an introduction
                        // is a tour, and a tour you cannot reverse is a slide
                        // show.
                        Button {
                            withAnimation(
                                reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)
                            ) {
                                page -= 1
                            }
                        } label: {
                            Label {
                                Text("Back", comment: "Onboarding action")
                            } icon: {
                                Image(systemName: "chevron.left")
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(palette.secondaryLabel)
                        .accessibilityLabel(Text("Back", comment: "Onboarding action"))
                    }

                    Spacer(minLength: 0)

                    Button {
                        // Straight to the page you sign in on, where the address
                        // already is.
                        withAnimation(
                            reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)
                        ) {
                            page = pageCount - 1
                            isAddressFocused = true
                        }
                    } label: {
                        Text("Skip", comment: "Onboarding action")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(palette.secondaryLabel)
                }
            } else {
                Button {
                    isAddressFocused = false
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { page -= 1 }
                } label: {
                    Label {
                        Text("Back", comment: "Onboarding action")
                    } icon: {
                        Image(systemName: "chevron.left")
                    }
                }
                .buttonStyle(.borderless)

            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: page)
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

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: AlohaMetrics.space4) {
                    if page.isHero {
                        // The app's own mark and wordmark: the first screen a person
                        // sees should look like the app they are about to use.
                        AlohaLogo()
                    } else {
                        // The symbol in Liquid Glass: on iPad and Mac a bare
                        // glyph on the window ground reads as an unfinished
                        // icon, while a glass tile reads as the app's own
                        // material — the same layer rows and toolbars use.
                        Image(systemName: page.symbol)
                            .font(.system(size: 34))
                            .foregroundStyle(palette.accent)
                            .frame(width: 84, height: 84)
                            .alohaGlassEffect(
                                .regular.tint(palette.accent.opacity(0.12)).interactive(),
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                            )
                            .accessibilityHidden(true)
                    }

                    VStack(spacing: AlohaMetrics.space2) {
                        if !page.isHero {
                            page.title
                                .font(.title2.weight(.semibold))
                                .multilineTextAlignment(.center)
                        }
                        page.detail
                            .font(.body)
                            .foregroundStyle(palette.secondaryLabel)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 380)
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
                }
                .frame(maxWidth: 460)
                .padding(.top, AlohaMetrics.space6)
                .padding(.bottom, AlohaMetrics.space4)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AlohaMetrics.space5)
        .scrollIndicators(.hidden)
    }
}
/// The reading experience, as it appears: the line between where you left off
/// and what arrived since.
///
/// This is the app's own idea — a feed that knows when you stopped reading —
/// and a page that *shows* it lands where a sentence about it would not.
private struct ReadingPreview: View {
    @Environment(\.alohaPalette) private var palette

    var body: some View {
        // Two rows the way rows look everywhere else: a face, a name, a line.
        // No mock content, no grey bars — the page's own sentence already says
        // what the feed does.
        VStack(spacing: 0) {
            previewRow(name: "Ada", text: "Shipping the new timeline today")
            Divider().padding(.leading, 52)
            previewRow(name: "Linus", text: "Photos from the lake")
        }
        .frame(maxWidth: 340)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("A preview of a timeline", comment: "Onboarding preview"))
    }

    private func previewRow(name: String, text: String) -> some View {
        HStack(spacing: AlohaMetrics.space3) {
            Circle()
                .fill(palette.separator.opacity(0.5))
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: text)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AlohaMetrics.space2)
    }
}

/// The screens the app runs on, as the devices themselves.
private struct DeviceRow: View {
    @Environment(\.alohaPalette) private var palette

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
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(palette.secondaryLabel)
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
            columns: [GridItem(.adaptive(minimum: 110), spacing: AlohaMetrics.space4)],
            spacing: AlohaMetrics.space4
        ) {
            ForEach(FeedMode.allCases) { mode in
                VStack(spacing: 6) {
                    Image(systemName: mode.symbolName)
                        .font(.title3)
                        .foregroundStyle(palette.accent)
                    Text(modeTitle(mode))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(palette.label)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AlohaMetrics.space3)
                .alohaGlassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(
                        cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
                )
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: 380)
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
    @State private var searchText = ""
    /// How many conversations are unread, for the badge on "Direct messages".
    /// The messages list writes it to the app group so this and the widgets
    /// read the same number (docs/05 §5). Observed, not read once on appear:
    /// a sidebar is on screen for hours, and a count read at launch was the
    /// count the badge kept.
    @AppStorage(AppGroup.unreadConversationsKey, store: AppGroup.defaults)
    private var unreadConversations = 0

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
        List(selection: optionalSelection) {
            // The shape of Nextcloud Social's own navigation: one primary
            // group of timelines and messages, then Explore, then everything
            // about your own account at the foot.
            Section {
                ForEach(session.visibleModes, id: \.self) { mode in
                    modeRow(mode)
                }

                Label {
                    Text("Direct messages", comment: "Sidebar item")
                } icon: {
                    Image(
                        systemName: selectedRoute == .conversations
                            ? "envelope.fill" : AlohaSymbol.envelope)
                }
                // `badge(0)` is not "no badge": it draws a zero, so every
                // account with an empty inbox would wear one. The optional
                // `Text` overload is the one that can mean "nothing at all".
                .badge(
                    unreadConversations > 0
                        ? Text(verbatim: String(unreadConversations)) : nil
                )
                .tag(SidebarItem.route(.conversations))
                .accessibilityLabel(
                    unreadConversations > 0
                        ? Text(
                            "Direct messages, \(unreadConversations) unread",
                            comment: "Sidebar item with badge")
                        : Text("Direct messages", comment: "Sidebar item"))
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
                // "Explore" was wrong over these: Discover is already in the
                // top group, and this section is lists, interests,
                // subscriptions and albums — the things a person gathers, not
                // where they stumble on new ones.
                Text("Library", comment: "Sidebar section")
            }

        }

        .listStyle(.sidebar)
        .searchable(
            text: $searchText, placement: .sidebar,
            prompt: Text("Search", comment: "Sidebar search field")
        )
        .onSubmit(of: .search, submitSearch)
        .navigationTitle(Text("Aloha Social", comment: "App name"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                AccountMenuButton(
                    session: session,
                    onOpen: { selection = .route($0) },
                    onAddAccount: onAddAccount,
                    showsBrowseDestinations: false)
            }
        }
    }

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
    ///
    /// Deliberately no `.listRowBackground(.clear)` and no hidden separator:
    /// both of those switch off what the system draws for a selected sidebar
    /// row, and a row that cannot look selected is the grobness a reviewer
    /// would notice first. The row background is the system's own, tinted by
    /// the accent.
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
