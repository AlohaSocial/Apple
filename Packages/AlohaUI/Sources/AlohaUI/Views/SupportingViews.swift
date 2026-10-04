// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

public struct WelcomeView: View {
    @Environment(\.alohaPalette) private var palette
    private let onAddAccount: () -> Void

    public init(onAddAccount: @escaping () -> Void) {
        self.onAddAccount = onAddAccount
    }

    public var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: AlohaMetrics.space5) {

            VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .padding(.top, AlohaMetrics.space6)

                Text("Aloha Social", comment: "App name")
                    .font(.largeTitle.weight(.bold))

                Text(
                    "Your people. Your conversations.",
                    comment: "Welcome subtitle"
                )
                .font(.body)
                .foregroundStyle(palette.secondaryLabel)
            }

            VStack(alignment: .leading, spacing: AlohaMetrics.space4) {
                welcomeDetail(symbol: "person.2", title: "Keep up with your people",
                    detail: "Read posts and share photos and videos from the accounts you follow.")
                welcomeDetail(symbol: "bubble.left", title: "Join the conversation",
                    detail: "Reply to a post or send a direct message.")
                welcomeDetail(symbol: "server.rack", title: "Use your existing account",
                    detail: "Connect your Nextcloud Social or Mastodon account using your server address.")
            }
            .padding(.vertical, AlohaMetrics.space3)

            Button(action: onAddAccount) {
                Text("Add your account", comment: "Welcome action")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(palette.accent)

            Text(
                "You sign in on your server. Aloha Social connects to your account.",
                comment: "Welcome footnote"
            )
            .font(.caption)
            .foregroundStyle(palette.tertiaryLabel)
        }
        .padding(AlohaMetrics.space5)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        }
        .background(palette.background)
    }

    private func welcomeDetail(symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: AlohaMetrics.space3) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(palette.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(palette.secondaryLabel)
            }
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
                    Label {
                        Text(title(for: mode))
                    } icon: {
                        Image(systemName: mode.symbolName)
                    }
                    .tag(SidebarItem.mode(mode))
                }

                row(
                    "Direct messages", symbol: AlohaSymbol.envelope, route: .conversations,
                    comment: "Sidebar item")
                row(
                    "Discover", symbol: "safari", route: .explore,
                    comment: "Sidebar item")
            }

            Section {
                row(
                    "Your lists", symbol: AlohaSymbol.list, route: .lists,
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
