// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import SwiftUI

/// What the introduction hands to sign-in: where to go, and what the probe
/// already found there, so the sign-in sheet does not ask for the address (or
/// probe the server) a second time.
public struct WelcomeSignInRequest {
    public var address: String
    public var outcome: ServerProbe.Outcome

    public init(address: String, outcome: ServerProbe.Outcome) {
        self.address = address
        self.outcome = outcome
    }
}

/// The introduction: two pages that say what is different about the app, then
/// the server.
///
/// It used to be eight pages before the server field, and some of them were
/// not true — six feeds where four are offered, numbers "only when you ask"
/// where they show by default, stories on servers that have none. Each page
/// now says one true thing that holds on any server, shows it with a mockup
/// that can be played with, and Skip reaches the server field in one tap.
/// Anything that depends on what the server can do is left until the server
/// is known.
public struct WelcomeView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    private let onAddAccount: (WelcomeSignInRequest?) -> Void
    private let showsConnectionStep: Bool

    @State private var page = 0
    @State private var serverAddress = ""

    /// The pages before the server step.
    private static let introPageCount = 2

    private var pageCount: Int { Self.introPageCount + (showsConnectionStep ? 1 : 0) }

    /// `showsConnectionStep: false` is the tour Settings opens: the same
    /// pages, without the server, closing at the end.
    public init(
        showsConnectionStep: Bool = true,
        onAddAccount: @escaping (WelcomeSignInRequest?) -> Void = { _ in }
    ) {
        self.showsConnectionStep = showsConnectionStep
        self.onAddAccount = onAddAccount
    }

    public var body: some View {
        ZStack {
            IntroBackdrop()

            VStack(spacing: 0) {
                header

                Group {
                    switch page {
                    case 0: feedsPage
                    case 1: calmPage
                    default: serverPage
                    }
                }
                .id(page)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .simultaneousGesture(swipe)

                footer
            }
        }
        .background(palette.background.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: page)
    }

    // MARK: - Chrome

    private var isLastPage: Bool { page == pageCount - 1 }

    private var header: some View {
        ZStack {
            if page > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.caption)
                        .foregroundStyle(palette.accent)
                    Text("Aloha Social", comment: "App name")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.secondaryLabel)
                }
                .accessibilityElement(children: .combine)
            }

            HStack {
                Spacer()

                if !showsConnectionStep {
                    // The tour from Settings: nothing to skip to, only out.
                    headerButton(String(localized: "Done", comment: "Onboarding action")) {
                        dismiss()
                    }
                } else if !isLastPage {
                    // One tap to the server field from any page.
                    headerButton(String(localized: "Skip", comment: "Onboarding action")) {
                        go(to: pageCount - 1)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func headerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(palette.label)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 5) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? palette.accent : palette.separator.opacity(0.55))
                        .frame(width: index == page ? 18 : 5, height: 5)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: page)
                }
            }
            .accessibilityHidden(true)

            HStack(spacing: 12) {
                if page > 0 {
                    Button {
                        go(to: page - 1)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back", comment: "Onboarding action")
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(palette.secondaryLabel)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(palette.surfaceRaised, in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(
                                palette.separator.opacity(0.5), lineWidth: 0.5)
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if !isLastPage {
                    IntroContinueButton(
                        title: String(localized: "Continue", comment: "Onboarding action")
                    ) {
                        go(to: page + 1)
                    }
                } else if !showsConnectionStep {
                    IntroContinueButton(
                        title: String(localized: "Done", comment: "Onboarding action")
                    ) {
                        dismiss()
                    }
                }
            }
            .frame(height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    // MARK: - Pages

    /// What the app is, and the thing it does that others do not: posts,
    /// photos and videos in one app, each kind in a feed made for it. The
    /// feeds are the four `FeedMode.offered`, so the mockup cannot claim
    /// more than the app has.
    private var feedsPage: some View {
        IntroPage(
            title: String(
                localized: "A calmer client for the social web.", comment: "Onboarding title"),
            detail: String(
                localized:
                    "Posts, photos and videos from the people you follow, each in a feed made for it. Tap along the bar to look.",
                comment: "Onboarding detail")
        ) {
            VStack(spacing: 24) {
                AlohaLogo()
                FeedsMockup()
            }
        }
    }

    /// What it does not do. Every sentence holds on any server: sensitive
    /// media is covered by default, the counts can be switched off (they
    /// show by default, `showPopularityCounts`), and the app collects
    /// nothing (docs/11 §3, the privacy manifest).
    private var calmPage: some View {
        IntroPage(
            title: String(localized: "Calm and private by design.", comment: "Onboarding title"),
            detail: String(
                localized:
                    "Sensitive media stays covered until you tap it, and the counts can go. No ads, no tracking: Aloha Social collects nothing about you.",
                comment: "Onboarding detail")
        ) {
            QuietMockup()
        }
    }

    private var serverPage: some View {
        WelcomeServerStep(
            address: $serverAddress,
            onContinue: { onAddAccount($0) },
            onLater: { onAddAccount(nil) })
    }

    // MARK: - Actions

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard
                    abs(value.translation.width) > abs(value.translation.height),
                    abs(value.translation.width) > 50
                else { return }
                if value.translation.width < 0 {
                    go(to: page + 1)
                } else {
                    go(to: page - 1)
                }
            }
    }

    private func go(to newPage: Int) {
        let target = min(max(newPage, 0), pageCount - 1)
        guard target != page else { return }
        if reduceMotion {
            page = target
        } else {
            withAnimation(.easeInOut(duration: 0.22)) { page = target }
        }
    }

}

// MARK: - Page frame

private struct IntroPage<Content: View>: View {
    @Environment(\.alohaPalette) private var palette

    let title: String
    let detail: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    // A fixed stage keeps the title in the same place from
                    // page to page, however tall the mockup is; centring the
                    // whole cluster is what makes the page sit on a phone
                    // instead of hanging under the header.
                    content()
                        .frame(maxWidth: .infinity, minHeight: 360, alignment: .center)

                    VStack(spacing: 8) {
                        Text(title)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryLabel)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 340)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(minHeight: geometry.size.height, alignment: .center)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

struct IntroCard<Content: View>: View {
    @Environment(\.alohaPalette) private var palette

    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(12)
            .background(
                palette.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerLarge, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AlohaMetrics.cornerLarge, style: .continuous)
                    .strokeBorder(palette.separator.opacity(0.5), lineWidth: 0.5)
            )
            .compositingGroup()
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }
}

struct IntroContinueButton: View {
    @Environment(\.alohaPalette) private var palette

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(palette.onAccent)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(palette.accent, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }
}

private struct IntroBackdrop: View {
    @Environment(\.alohaPalette) private var palette

    var body: some View {
        ZStack {
            palette.background
            RadialGradient(
                colors: [palette.accent.opacity(0.1), .clear],
                center: .top, startRadius: 10, endRadius: 460
            )
            .offset(y: -120)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Mockups

private struct FeedsMockup: View {
    @Environment(\.alohaPalette) private var palette
    @State private var selected: FeedMode = .home

    var body: some View {
        IntroCard {
            VStack(spacing: 9) {
                HStack {
                    Text(modeTitle(selected))
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("Following", comment: "Onboarding mockup")
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryLabel)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(palette.accent.opacity(0.22))
                            .frame(width: 20, height: 20)
                        Capsule().fill(palette.label.opacity(0.22)).frame(width: 56, height: 4)
                        Spacer()
                    }
                    Capsule().fill(palette.separator).frame(height: 5)
                    Capsule().fill(palette.separator.opacity(0.7)).frame(width: 118, height: 4)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: modeColors(selected), startPoint: .topLeading,
                                endPoint: .bottomTrailing)
                        )
                        .frame(height: 72)
                        .overlay(
                            Image(systemName: selected.symbolName)
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.9)))
                }
                .padding(9)
                .background(
                    palette.background.opacity(0.65),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 0) {
                    ForEach(FeedMode.offered) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { selected = mode }
                        } label: {
                            Image(systemName: mode.symbolName)
                                .font(.caption)
                                .foregroundStyle(
                                    selected == mode ? palette.accent : palette.tertiaryLabel
                                )
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(modeTitle(mode)))
                        .accessibilityAddTraits(
                            selected == mode ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(palette.background.opacity(0.65), in: Capsule())
            }
            .frame(width: 252)
        }
    }

    /// The tab bar's own names, so the mockup reads as the app will.
    private func modeTitle(_ mode: FeedMode) -> String {
        switch mode {
        case .home: String(localized: "My Feed", comment: "Mode title")
        case .photos: String(localized: "Photos", comment: "Mode title")
        case .video: String(localized: "Videos", comment: "Mode title")
        case .shorts: String(localized: "Shorts", comment: "Mode title")
        case .news: String(localized: "News", comment: "Mode title")
        case .audio: String(localized: "Audio", comment: "Mode title")
        }
    }

    private func modeColors(_ mode: FeedMode) -> [Color] {
        switch mode {
        case .home: [palette.accent.opacity(0.55), palette.accentMuted]
        case .photos: [palette.favourite.opacity(0.5), palette.accent.opacity(0.35)]
        case .video: [palette.boost.opacity(0.55), palette.accent.opacity(0.3)]
        case .shorts: [palette.favourite.opacity(0.55), palette.boost.opacity(0.35)]
        case .news: [palette.secondaryLabel.opacity(0.45), palette.accent.opacity(0.3)]
        case .audio: [palette.accentMuted, palette.favourite.opacity(0.35)]
        }
    }
}

private struct QuietMockup: View {
    @Environment(\.alohaPalette) private var palette
    @State private var blurred = true
    @State private var numbers = true

    var body: some View {
        IntroCard {
            VStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    palette.accent.opacity(0.5), palette.favourite.opacity(0.35),
                                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(height: 96)
                        .blur(radius: blurred ? 12 : 0)

                    if blurred {
                        Image(systemName: "eye.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.black.opacity(0.3), in: Circle())
                    }
                }

                HStack(spacing: 14) {
                    HStack(spacing: 3) {
                        Image(systemName: AlohaSymbol.favourite)
                        if numbers { Text(verbatim: "24").monospacedDigit() }
                    }
                    HStack(spacing: 3) {
                        Image(systemName: AlohaSymbol.boost)
                        if numbers { Text(verbatim: "8").monospacedDigit() }
                    }
                    Spacer()
                    Image(systemName: AlohaSymbol.bookmark)
                }
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)

                VStack(spacing: 0) {
                    Toggle(isOn: $blurred) {
                        Text("Blur sensitive media", comment: "Onboarding demo toggle")
                            .font(.caption)
                    }
                    .tint(palette.accent)
                    .frame(minHeight: 38)

                    Divider()

                    Toggle(isOn: $numbers) {
                        Text("Show the numbers", comment: "Onboarding demo toggle")
                            .font(.caption)
                    }
                    .tint(palette.accent)
                    .frame(minHeight: 38)
                }
                .padding(.horizontal, 10)
                .background(
                    palette.background.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .frame(width: 270)
            .animation(.easeInOut(duration: 0.2), value: blurred)
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
        .collections(accountID: nil),
        .followRequests, .favourites, .bookmarks, .archived, .statistics, .safety, .settings,
    ]
}

extension View {
    /// The selected sidebar row wears the server's colour in its words as
    /// well as its symbol. The system's own selection is left as it is —
    /// on the Mac that is a neutral capsule, which says "selected" and
    /// nothing about whose app this is.
    @ViewBuilder
    fileprivate func sidebarSelectionAccent(_ isSelected: Bool) -> some View {
        #if os(macOS)
            modifier(SidebarSelectionAccent(isSelected: isSelected))
        #else
            self
        #endif
    }
}

#if os(macOS)
    private struct SidebarSelectionAccent: ViewModifier {
        let isSelected: Bool

        func body(content: Content) -> some View {
            // The tile carries the colour; the words stay the label's own
            // and only gain weight, at a size that sits with a larger tile.
            content
                .labelStyle(SidebarRowLabelStyle())
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .padding(.vertical, 2)
        }
    }
#endif

#if os(macOS)
    /// A sidebar row with room between its tile and its words: the system's
    /// label spacing is cut for a bare symbol, and a tile nearly twice that
    /// width sat hard against the text.
    private struct SidebarRowLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 10) {
                configuration.icon
                configuration.title
            }
        }
    }

    /// A place's symbol in the Mac's sidebar: the system's own, in the
    /// accent, a little larger than a list's default and with no tile behind
    /// it — the sidebar of Mail and Notes, which is the quietest thing a
    /// sidebar can be and the one a Mac user already reads without looking.
    struct SidebarGlyph: View {
        @Environment(\.alohaPalette) private var palette
        private let symbolName: String

        init(_ symbolName: String) {
            self.symbolName = symbolName
        }

        var body: some View {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.accent)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
        }
    }

    /// A sidebar row that says what is behind it: a count in the accent, a
    /// line of detail under the title, and the faces of who it is from.
    struct LiveSidebarRow: View {
        @Environment(\.alohaPalette) private var palette

        let title: Text
        let symbolName: String
        let isSelected: Bool
        let count: Int
        var detail: Text?
        var faces: [Account] = []

        var body: some View {
            HStack(spacing: 10) {
                SidebarGlyph(symbolName)
                VStack(alignment: .leading, spacing: 1) {
                    title
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    if let detail {
                        detail
                            .font(.system(size: 11))
                            .foregroundStyle(palette.secondaryLabel)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if !faces.isEmpty {
                    HStack(spacing: -6) {
                        ForEach(faces.prefix(3)) { account in
                            AvatarView(account: account, size: 18)
                        }
                    }
                }
                if count > 0 {
                    Text(count, format: .number)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(palette.onAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(palette.accent, in: Capsule())
                }
            }
            .padding(.vertical, 2)
        }
    }
#endif

public struct SidebarView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    @Binding private var selection: SidebarItem
    /// Bound for the app shell to write into when a feed source changes; the
    /// sidebar itself no longer reads it, because a source is a property of
    /// the mode's screen rather than of the navigation.
    @Binding private var selectedSource: TimelineSource
    @State private var searchText = ""
    #if os(macOS)
        @State private var pinnedLists: [AccountList] = []
        @State private var pinnedTags: [Tag] = []
        /// The newest few conversations, for the line and the faces on the
        /// Direct messages row.
        @State private var recentConversations: [Conversation] = []
        /// Who wrote last and the start of what they wrote, worked out when
        /// the conversations arrive rather than each time the row is drawn.
        @State private var latestMessage: String?
    #endif
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

                #if os(macOS)
                    // On the Mac these two rows say what is waiting behind
                    // them: how many, and for messages who and what, so the
                    // sidebar is worth a glance without opening either.
                    LiveSidebarRow(
                        title: Text("Activities", comment: "Sidebar item"),
                        symbolName: selectedRoute == .notifications
                            ? AlohaSymbol.notificationsFilled : AlohaSymbol.notifications,
                        isSelected: selectedRoute == .notifications,
                        count: unreadActivities,
                        detail: unreadActivities > 0
                            ? Text(
                                "^[\(unreadActivities) new activity](inflect: true)",
                                comment: "Sidebar row detail: unread activities")
                            : nil
                    )
                    .tag(SidebarItem.route(.notifications))
                    .accessibilityLabel(
                        unreadActivities > 0
                            ? Text(
                                "Activities, \(unreadActivities) unread",
                                comment: "Sidebar item with badge")
                            : Text("Activities", comment: "Sidebar item"))

                    LiveSidebarRow(
                        title: Text("Direct messages", comment: "Sidebar item"),
                        symbolName: selectedRoute == .conversations
                            ? AlohaSymbol.directMessageFilled : AlohaSymbol.directMessage,
                        isSelected: selectedRoute == .conversations,
                        count: unreadConversations,
                        detail: latestMessageLine,
                        faces: recentCorrespondents
                    )
                    .tag(SidebarItem.route(.conversations))
                    .accessibilityLabel(
                        unreadConversations > 0
                            ? Text(
                                "Direct messages, \(unreadConversations) unread",
                                comment: "Sidebar item with badge")
                            : Text("Direct messages", comment: "Sidebar item"))
                #else
                    Label {
                        Text("Activities", comment: "Sidebar item")
                    } icon: {
                        Image(
                            systemName: selectedRoute == .notifications
                                ? AlohaSymbol.notificationsFilled : AlohaSymbol.notifications)
                    }
                    .badge(unreadActivities > 0 ? Text(verbatim: String(unreadActivities)) : nil)
                    .sidebarSelectionAccent(selectedRoute == .notifications)
                    .tag(SidebarItem.route(.notifications))
                    .accessibilityLabel(
                        unreadActivities > 0
                            ? Text(
                                "Activities, \(unreadActivities) unread",
                                comment: "Sidebar item with badge")
                            : Text("Activities", comment: "Sidebar item"))

                    Label {
                        Text("Direct messages", comment: "Sidebar item")
                    } icon: {
                        Image(
                            systemName: selectedRoute == .conversations
                                ? AlohaSymbol.directMessageFilled : AlohaSymbol.directMessage)
                    }
                    // `badge(0)` is not "no badge": it draws a zero, so every
                    // account with an empty inbox would wear one. The optional
                    // `Text` overload is the one that can mean "nothing at all".
                    .badge(
                        unreadConversations > 0
                            ? Text(verbatim: String(unreadConversations)) : nil
                    )
                    .sidebarSelectionAccent(selectedRoute == .conversations)
                    .tag(SidebarItem.route(.conversations))
                    .accessibilityLabel(
                        unreadConversations > 0
                            ? Text(
                                "Direct messages, \(unreadConversations) unread",
                                comment: "Sidebar item with badge")
                            : Text("Direct messages", comment: "Sidebar item"))
                #endif
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
                if session.capabilities.collections {
                    row(
                        "Collections", symbol: "rectangle.stack",
                        route: .collections(accountID: nil),
                        comment: "Sidebar item")
                }
            } header: {
                // "Explore" was wrong over these: Discover is already in the
                // top group, and this section is lists and collections —
                // the things a person gathers, not where they stumble on new
                // ones.
                Text("Library", comment: "Sidebar section")
            }

            #if os(macOS)
                // The reader's own lists and the hashtags they follow, one
                // click away rather than two screens in: a Mac sidebar has
                // the height for them.
                if !pinnedLists.isEmpty {
                    Section {
                        ForEach(pinnedLists.prefix(6)) { list in
                            let route = Route.timeline(
                                TimelineKey(mode: .home, source: .list(id: list.id)))
                            Label {
                                Text(verbatim: list.title)
                            } icon: {
                                SidebarGlyph("list.bullet")
                            }
                            .sidebarSelectionAccent(selectedRoute == route)
                            .tag(SidebarItem.route(route))
                        }
                    } header: {
                        Text("Lists", comment: "Lists section")
                    }
                }
                if !pinnedTags.isEmpty {
                    Section {
                        ForEach(pinnedTags.prefix(6)) { tag in
                            Label {
                                Text(verbatim: tag.name)
                            } icon: {
                                SidebarGlyph("number")
                            }
                            .sidebarSelectionAccent(selectedRoute == .hashtag(tag.name))
                            .tag(SidebarItem.route(.hashtag(tag.name)))
                        }
                    } header: {
                        Text("Followed hashtags", comment: "Lists section")
                    }
                }
            #endif

        }

        .listStyle(.sidebar)
        #if !os(macOS)
            .searchable(
                text: $searchText, placement: .sidebar,
                prompt: Text("Search", comment: "Sidebar search field")
            )
            .onSubmit(of: .search, submitSearch)
        #endif
        .navigationTitle(Text("Aloha Social", comment: "App name"))
        #if os(macOS)
            .task(id: session.id) {
                async let lists = try? session.client.decode(
                    LossyArray<AccountList>.self, from: Endpoint.lists.all)
                async let tags = try? session.client.decode(
                    LossyArray<Tag>.self, from: Endpoint.tags.followed(limit: 20))
                pinnedLists = await lists?.elements ?? []
                pinnedTags = await tags?.elements ?? []
            }
            // Asked again whenever the unread count moves, so the line under
            // Direct messages is the message that moved it.
            .task(id: MessagesKey(account: session.id, unread: unreadConversations)) {
                let page = try? await session.client.decode(
                    LossyArray<Conversation>.self, from: Endpoint.timelines.conversations(limit: 3))
                recentConversations = page?.elements ?? []
                latestMessage = recentConversations.first?.lastStatus.flatMap { last in
                    let status = last.displayed
                    let words =
                        status.spoilerText.isEmpty
                        ? StatusHTMLParser().plainText(status.content)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        : status.spoilerText
                    return words.isEmpty ? nil : status.account.bestDisplayName + ": " + words
                }
            }
            // The server's colour, as light from the top of the sidebar: the
            // one place the window says whose Nextcloud this is before a
            // word of it is read.
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [palette.accent.opacity(0.20), palette.accent.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 200)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            // At the sidebar's foot, with the name beside the face, as on
            // iPad. In the window's toolbar the system drew it as one more
            // glass capsule beside the sidebar toggle, holding a pair of
            // initials: a control that looked like nothing in particular.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AccountMenuButton(
                    session: session,
                    onOpen: { selection = .route($0) },
                    onAddAccount: onAddAccount,
                    showsBrowseDestinations: false, showsName: true
                )
                .padding(.horizontal, AlohaMetrics.space3)
                .padding(.vertical, AlohaMetrics.space2)
                // A link or a passage dragged onto your own face starts a
                // post with it.
                .dropDestination(for: String.self) { items, _ in
                    guard let dropped = items.first, !dropped.isEmpty else { return false }
                    NotificationCenter.default.post(
                        name: RouteResolver.composeRequested, object: nil,
                        userInfo: ["draft": dropped])
                    return true
                }
                .dropDestination(for: URL.self) { items, _ in
                    guard let dropped = items.first else { return false }
                    NotificationCenter.default.post(
                        name: RouteResolver.composeRequested, object: nil,
                        userInfo: ["draft": dropped.absoluteString])
                    return true
                }
            }
        #else
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    AccountMenuButton(
                        session: session,
                        onOpen: { selection = .route($0) },
                        onAddAccount: onAddAccount,
                        showsBrowseDestinations: false)
                }
            }
        #endif
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
            #if os(macOS)
                SidebarGlyph(isSelected ? mode.selectedSymbolName : mode.symbolName)
            #else
                Image(systemName: isSelected ? mode.selectedSymbolName : mode.symbolName)
            #endif
        }
        .sidebarSelectionAccent(isSelected)
        .tag(SidebarItem.mode(mode))
        .accessibilityLabel(Text(title(for: mode)))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    #if os(macOS)
        private struct MessagesKey: Hashable {
            let account: UUID
            let unread: Int
        }

        /// The people in the newest conversations, other than the reader.
        private var recentCorrespondents: [Account] {
            var seen = Set<String>()
            return recentConversations.flatMap(\.accounts).filter {
                $0.id != session.snapshot.serverAccountID && seen.insert($0.id).inserted
            }
        }

        /// "Nina: see you at five" — who wrote last, and the start of it.
        private var latestMessageLine: Text? {
            latestMessage.map { Text(verbatim: $0) }
        }
    #endif

    /// Submitting the system's search bar navigates to the results, rather
    /// than leaving the typed query where the system put it.
    private func submitSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        selection = .route(.search(query: query))
    }

    private var unreadActivities: Int {
        environment.sync.unreadCounts[session.id] ?? 0
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
            #if os(macOS)
                SidebarGlyph(symbol)
            #else
                Image(systemName: symbol)
            #endif
        }
        .sidebarSelectionAccent(selectedRoute == route)
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
