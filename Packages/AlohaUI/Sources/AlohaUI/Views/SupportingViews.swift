// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

public struct WelcomeView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics

    private let onAddAccount: () -> Void

    public init(onAddAccount: @escaping () -> Void) {
        self.onAddAccount = onAddAccount
    }

    /// What the introduction says, one page per promise the app makes. Each
    /// page is a sentence somebody can agree with before they hand over a
    /// server address — the first screen is where the app explains itself,
    /// not a splash to be tapped away.
    private var pages: [OnboardingPage] {
        [
            OnboardingPage(
                symbol: "server.rack",
                title: Text("Your server, your rules", comment: "Onboarding title"),
                detail: Text(
                    "Aloha Social is a client, not a platform. Sign in to the Nextcloud Social or Mastodon server you already use — your posts, photos and messages stay there.",
                    comment: "Onboarding detail")),
            OnboardingPage(
                symbol: "square.stack.3d.up.fill",
                title: Text("Six feeds, each its own screen", comment: "Onboarding title"),
                detail: Text(
                    "Home is everything. Photos is a grid of pictures. Video remembers where you got to. Shorts is full screen. News and Audio are off until you ask for them.",
                    comment: "Onboarding detail")),
            OnboardingPage(
                symbol: "bubble.left.and.exclamationmark.right",
                title: Text("The whole fediverse, one inbox", comment: "Onboarding title"),
                detail: Text(
                    "Follow people on other servers and read everything in one place. Direct messages, notifications and mentions all work across the federation.",
                    comment: "Onboarding detail")),
            OnboardingPage(
                symbol: "lock.shield.fill",
                title: Text("Quiet by default", comment: "Onboarding title"),
                detail: Text(
                    "Media behind a content warning stays blurred. Popularity counts can be switched off entirely. Digest notifications wait for the times you pick.",
                    comment: "Onboarding detail")),
        ]
    }

    @State private var page = 0

    public var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, content in
                    OnboardingPageView(page: content)
                        .tag(index)
                }
            }
            #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
            #endif

            footer
                .padding(.horizontal, metrics.space5)
                .padding(.bottom, metrics.space5)
        }
        .background(palette.background.ignoresSafeArea())
    }

    private var footer: some View {
        VStack(spacing: metrics.space3) {
            // Owned rather than `.tabViewStyle(.page)`'s indicator: that style
            // does not exist on every platform, and four dots are cheap.
            HStack(spacing: metrics.space2) {
                ForEach(pages.indices, id: \.self) { index in
                    Circle()
                        .fill(index == page ? palette.accent : palette.separator)
                        .frame(width: index == page ? 9 : 6, height: index == page ? 9 : 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: page)
                }
            }
            .accessibilityHidden(true)

            let isLast = page == pages.count - 1
            Button {
                if isLast {
                    onAddAccount()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { page += 1 }
                }
            } label: {
                Text(
                    isLast ? "Add your account" : "Continue", comment: "Onboarding action"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.alohaProminent)

            if isLast {
                Text(
                    "You will need the address of your server — for example aloha.example.org. You sign in on your server; Aloha Social only connects.",
                    comment: "Onboarding footnote")
                    .font(.caption)
                    .foregroundStyle(palette.tertiaryLabel)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            } else {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        page = pages.count - 1
                    }
                } label: {
                    Text("Skip", comment: "Onboarding action")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(palette.secondaryLabel)
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
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics

    var body: some View {
        VStack(spacing: metrics.space5) {
            Spacer(minLength: 0)

            Image(systemName: page.symbol)
                .font(.system(size: 62))
                .foregroundStyle(palette.accent)
                .frame(width: 148, height: 148)
                .unifiedGlass(
                    .regular,
                    in: RoundedRectangle(
                        cornerRadius: AlohaMetrics.cornerLarge * 2, style: .continuous))
                .accessibilityHidden(true)

            VStack(spacing: metrics.space3) {
                page.title
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                page.detail
                    .font(.body)
                    .foregroundStyle(palette.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.space5)
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
        .background(
            palette.surfaceRaised,
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
        List(selection: optionalSelection) {
            Section {
                ForEach(session.visibleModes, id: \.self) { mode in
                    modeRow(mode)
                        .tag(SidebarItem.mode(mode))
                        .listRowBackground(
                            selection == .mode(mode)
                                ? palette.accent.opacity(0.12) : Color.clear
                        )
                }

                row(
                    "Direct messages", symbol: selectedRoute == .conversations ? "envelope.fill" : AlohaSymbol.envelope, route: .conversations,
                    comment: "Sidebar item")
                row(
                    "Discover", symbol: selectedRoute == .explore ? "safari.fill" : "safari", route: .explore,
                    comment: "Sidebar item")
            }

            Section {
                row(
                    "Your lists", symbol: selectedRoute == .lists ? "list.bullet.rectangle.fill" : "list.bullet.rectangle", route: .lists,
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
    private var accountDrawer: some View {
        VStack(spacing: 0) {
            Divider()

            if isAccountExpanded {
                // Sized to its rows, and only scrolls when there are more than
                // fit: a ScrollView on its own claims all the height offered.
                ViewThatFits(in: .vertical) {
                    drawerContent
                    ScrollView { drawerContent }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            accountToggle
        }
        .background(palette.surface)
    }

    private var drawerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                Divider().padding(.vertical, AlohaMetrics.space1)
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

            Divider().padding(.vertical, AlohaMetrics.space1)
            drawerButton(
                String(localized: "Add account…", comment: "Account switcher action"),
                symbol: "person.badge.plus",
                accessibilityLabel: Text("Add account", comment: "Account switcher action"),
                action: onAddAccount)
        }
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

                Image(systemName: "chevron.up")
                    .font(.caption2)
                    .foregroundStyle(palette.tertiaryLabel)
                    .rotationEffect(.degrees(isAccountExpanded ? 180 : 0))
            }
            .padding(AlohaMetrics.space3)
            .contentShape(Rectangle())
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
        Button(action: action) {
            HStack(spacing: AlohaMetrics.space3) {
                Image(systemName: symbol)
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? palette.accent : palette.secondaryLabel)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AlohaMetrics.space3)
            .padding(.vertical, AlohaMetrics.space2)
            .background(
                isSelected ? palette.accent.opacity(0.12) : .clear,
                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
            )
            .padding(.horizontal, AlohaMetrics.space2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
