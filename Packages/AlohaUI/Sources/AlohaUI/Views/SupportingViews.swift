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

    @State private var page = 0
    @State private var selectedMode: FeedMode = .home
    @State private var demoBlur = true
    @State private var demoCounts = true
    @State private var serverAddress = ""
    @FocusState private var isAddressFocused: Bool

    private static let pageCount = 4

    public init(onAddAccount: @escaping (String?) -> Void = { _ in }) {
        self.onAddAccount = onAddAccount
    }

    public var body: some View {
        ZStack {
            IntroBackdrop()

            VStack(spacing: 0) {
                header

                Group {
                    switch page {
                    case 0: welcomePage
                    case 1: feedsPage
                    case 2: quietPage
                    default: serverPage
                    }
                }
                .id(page)
                .transition(
                    reduceMotion
                        ? .opacity : .opacity.combined(with: .offset(y: 14))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded { value in
                            guard
                                abs(value.translation.width)
                                    > abs(value.translation.height),
                                abs(value.translation.width) > 60
                            else { return }
                            if value.translation.width < 0 {
                                go(to: page + 1)
                            } else {
                                go(to: page - 1)
                            }
                        }
                )

                footer
            }
        }
        .background(palette.background.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: page)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.title3)
                .foregroundStyle(palette.accent)
            Text("Aloha Social", comment: "App name")
                .font(.subheadline.weight(.semibold))

            Spacer()

            if page < Self.pageCount - 1 {
                Button {
                    go(to: Self.pageCount - 1)
                } label: {
                    Text("Skip", comment: "Onboarding action")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.secondaryLabel)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityHint(
                    Text("Jumps to the server sign-in", comment: "Onboarding skip hint"))
            }
        }
        .padding(.horizontal, AlohaMetrics.space5)
        .padding(.top, AlohaMetrics.space3)
    }

    private var footer: some View {
        VStack(spacing: AlohaMetrics.space3) {
            HStack(spacing: 5) {
                ForEach(0..<Self.pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= page ? palette.accent : palette.separator.opacity(0.45))
                        .frame(height: 3)
                }
            }
            .accessibilityHidden(true)
            .animation(.easeInOut(duration: 0.25), value: page)

            HStack(spacing: AlohaMetrics.space3) {
                if page > 0 {
                    Button {
                        go(to: page - 1)
                    } label: {
                        Label {
                            Text("Back", comment: "Onboarding action")
                        } icon: {
                            Image(systemName: "chevron.left")
                        }
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.secondaryLabel)
                }

                Spacer()

                if page < Self.pageCount - 1 {
                    Button {
                        go(to: page + 1)
                    } label: {
                        HStack(spacing: 6) {
                            Text("Continue", comment: "Onboarding action")
                            Image(systemName: "arrow.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, AlohaMetrics.space5)
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.alohaProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Text(verbatim: "\(page + 1) / \(Self.pageCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(palette.tertiaryLabel)
                }
            }
        }
        .padding(.horizontal, AlohaMetrics.space5)
        .padding(.bottom, AlohaMetrics.space4)
    }

    // MARK: - Pages

    private var welcomePage: some View {
        ScrollView {
            VStack(spacing: AlohaMetrics.space4) {
                IntroMark()

                VStack(spacing: AlohaMetrics.space2) {
                    Text("Welcome to Aloha Social", comment: "Onboarding title")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(
                        "A calmer client for the social web. Your server, your feeds, your pace.",
                        comment: "Onboarding detail"
                    )
                    .font(.body)
                    .foregroundStyle(palette.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                }

                VStack(spacing: AlohaMetrics.space2) {
                    IntroFeature(
                        symbol: "server.rack",
                        title: String(localized: "Your server", comment: "Onboarding feature"),
                        detail: String(
                            localized: "Sign in to your own instance — no one in the middle.",
                            comment: "Onboarding feature detail"))
                    IntroFeature(
                        symbol: "square.grid.2x2",
                        title: String(localized: "Six feeds", comment: "Onboarding feature"),
                        detail: String(
                            localized:
                                "Home, photos, video, shorts, news and audio, each its own screen.",
                            comment: "Onboarding feature detail"))
                    IntroFeature(
                        symbol: "moon.stars",
                        title: String(localized: "Quiet by default", comment: "Onboarding feature"),
                        detail: String(
                            localized: "No counts shouting, no autoplay, no endless noise.",
                            comment: "Onboarding feature detail"))
                }
                .frame(maxWidth: 420)

                HStack(spacing: AlohaMetrics.space2) {
                    Text("Swipe or tap Continue", comment: "Onboarding hint")
                    Image(systemName: "arrow.right")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.tertiaryLabel)
                .padding(.top, AlohaMetrics.space2)
            }
            .padding(.horizontal, AlohaMetrics.space5)
            .padding(.vertical, AlohaMetrics.space4)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var feedsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlohaMetrics.space4) {
                VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                    Text("Six feeds, one app", comment: "Onboarding title")
                        .font(.title.weight(.bold))
                    Text(
                        "Tap a feed to see what it becomes. The same six live in the tab bar.",
                        comment: "Onboarding detail"
                    )
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 92), spacing: AlohaMetrics.space2)
                    ], spacing: AlohaMetrics.space2
                ) {
                    ForEach(FeedMode.offered) { mode in
                        Button {
                            withAnimation(.snappy(duration: 0.22)) { selectedMode = mode }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: mode.symbolName)
                                    .font(.title3)
                                Text(modeTitle(mode))
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(
                                selectedMode == mode ? palette.onAccent : palette.label
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AlohaMetrics.space3)
                            .background(
                                selectedMode == mode ? palette.accent : palette.surfaceRaised,
                                in: RoundedRectangle(
                                    cornerRadius: 16, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(
                                        selectedMode == mode
                                            ? palette.accent : palette.separator.opacity(0.4),
                                        lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(
                            selectedMode == mode ? [.isButton, .isSelected] : .isButton)
                    }
                }

                HStack(alignment: .top, spacing: AlohaMetrics.space3) {
                    Image(systemName: selectedMode.symbolName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 46, height: 46)
                        .background(
                            palette.accent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(modeTitle(selectedMode))
                            .font(.headline)
                        Text(modeDetail(selectedMode))
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(AlohaMetrics.space3)
                .background(
                    palette.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                miniTabBar
            }
            .padding(.horizontal, AlohaMetrics.space5)
            .padding(.vertical, AlohaMetrics.space4)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var quietPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlohaMetrics.space4) {
                VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                    Text("Quiet by default", comment: "Onboarding title")
                        .font(.title.weight(.bold))
                    Text(
                        "Try it: these switches change the card below, not your settings yet.",
                        comment: "Onboarding detail"
                    )
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                }

                demoCard

                VStack(spacing: AlohaMetrics.space2) {
                    Toggle(isOn: $demoBlur) {
                        Label {
                            Text("Blur sensitive media", comment: "Onboarding demo toggle")
                        } icon: {
                            Image(systemName: "eye.slash")
                        }
                    }
                    Toggle(isOn: $demoCounts) {
                        Label {
                            Text("Show numbers", comment: "Onboarding demo toggle")
                        } icon: {
                            Image(systemName: "number")
                        }
                    }
                }
                .font(.subheadline)
                .tint(palette.accent)
                .padding(AlohaMetrics.space3)
                .background(
                    palette.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(
                    "You can change all of this later in Settings.", comment: "Onboarding footnote"
                )
                .font(.caption)
                .foregroundStyle(palette.tertiaryLabel)
            }
            .padding(.horizontal, AlohaMetrics.space5)
            .padding(.vertical, AlohaMetrics.space4)
            .frame(maxWidth: 480, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var serverPage: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: AlohaMetrics.space4) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(palette.accent)
                        .frame(width: 92, height: 92)
                        .background(
                            palette.accent.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 26, style: .continuous))

                    VStack(spacing: AlohaMetrics.space2) {
                        Text("Where do you socialize?", comment: "Onboarding server title")
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(
                            "Enter your server's address. If you already have an account, its sign-in page opens; if not, you can create one there.",
                            comment: "Onboarding server detail"
                        )
                        .font(.body)
                        .foregroundStyle(palette.secondaryLabel)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    }

                    VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                        TextField(
                            String(
                                localized: "mastodon.social",
                                comment: "Onboarding server field prompt"),
                            text: $serverAddress
                        )
                        #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        #endif
                        .textFieldStyle(.roundedBorder)
                        .focused($isAddressFocused)
                        .onSubmit(start)
                        .accessibilityLabel(
                            Text("Server address", comment: "Onboarding server field"))

                        Button(action: start) {
                            Text("Continue", comment: "Onboarding action")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.alohaProminent)
                        .keyboardShortcut(.defaultAction)

                        Text(
                            "Aloha Social has no account of its own.",
                            comment: "Onboarding footnote"
                        )
                        .font(.caption)
                        .foregroundStyle(palette.tertiaryLabel)
                    }
                    .frame(maxWidth: 400)
                    .padding(AlohaMetrics.space4)
                    .background(
                        palette.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .frame(maxWidth: 460)
                .padding(.horizontal, AlohaMetrics.space5)
                .padding(.vertical, AlohaMetrics.space4)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("welcome-sign-in-content")
        }
    }

    // MARK: - Pieces

    private var miniTabBar: some View {
        HStack(spacing: 0) {
            ForEach(FeedMode.offered) { mode in
                VStack(spacing: 3) {
                    Image(systemName: mode.symbolName)
                        .font(.caption)
                    Text(modeTitle(mode))
                        .font(.system(size: 8, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(selectedMode == mode ? palette.accent : palette.tertiaryLabel)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, AlohaMetrics.space2)
        .padding(.vertical, AlohaMetrics.space2)
        .background(
            palette.surfaceRaised,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.separator.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("A preview of the tab bar", comment: "Onboarding tab bar preview"))
    }

    private var demoCard: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            HStack(spacing: AlohaMetrics.space2) {
                Circle()
                    .fill(palette.favourite.opacity(0.25))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Text("M", comment: "Onboarding demo avatar")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(palette.favourite))
                Text("Mira", comment: "Onboarding demo name")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("now", comment: "Onboarding demo time")
                    .font(.caption2)
                    .foregroundStyle(palette.tertiaryLabel)
            }

            ZStack {
                LinearGradient(
                    colors: [palette.accent.opacity(0.55), palette.favourite.opacity(0.4)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(height: 140)
                .blur(radius: demoBlur ? 10 : 0)

                if demoBlur {
                    VStack(spacing: 4) {
                        Image(systemName: "eye.slash.fill")
                            .font(.title3)
                        Text("Sensitive", comment: "Onboarding demo blur label")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(AlohaMetrics.space3)
                    .background(
                        .black.opacity(0.3),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: AlohaMetrics.space4) {
                demoMetric(AlohaSymbol.favourite, count: demoCounts ? "24" : nil)
                demoMetric(AlohaSymbol.boost, count: demoCounts ? "8" : nil)
                demoMetric(AlohaSymbol.reply, count: demoCounts ? "3" : nil)
                Spacer()
                Image(systemName: AlohaSymbol.bookmark)
            }
            .font(.footnote)
            .foregroundStyle(palette.secondaryLabel)
        }
        .padding(AlohaMetrics.space3)
        .background(
            palette.surfaceRaised,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.separator.opacity(0.4), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.2), value: demoBlur)
        .animation(.easeInOut(duration: 0.2), value: demoCounts)
    }

    private func demoMetric(_ symbol: String, count: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if let count {
                Text(verbatim: count).monospacedDigit()
            }
        }
    }

    // MARK: - Actions

    private func go(to newPage: Int) {
        let target = min(max(newPage, 0), Self.pageCount - 1)
        guard target != page else { return }
        if reduceMotion {
            page = target
        } else {
            withAnimation(.easeInOut(duration: 0.28)) { page = target }
        }
        if target == Self.pageCount - 1 {
            isAddressFocused = true
        }
    }

    private func start() {
        let address = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        onAddAccount(address.isEmpty ? nil : address)
    }

    // MARK: - Names

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

    private func modeDetail(_ mode: FeedMode) -> String {
        switch mode {
        case .home:
            String(
                localized: "The people you follow, in the order they posted.",
                comment: "Feed mode detail")
        case .photos:
            String(
                localized: "Pictures first: a grid that opens into full posts.",
                comment: "Feed mode detail")
        case .video:
            String(
                localized: "Longer video, with a player that remembers where you stopped.",
                comment: "Feed mode detail")
        case .shorts:
            String(
                localized: "Vertical clips, one at a time, no autoplay after the first.",
                comment: "Feed mode detail")
        case .news:
            String(
                localized: "Links and headlines, kept apart from the conversation.",
                comment: "Feed mode detail")
        case .audio:
            String(
                localized: "Podcasts and voice posts, with a queue you control.",
                comment: "Feed mode detail")
        }
    }
}

private struct IntroFeature: View {
    @Environment(\.alohaPalette) private var palette

    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: AlohaMetrics.space3) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 36, height: 36)
                .background(
                    palette.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(AlohaMetrics.space3)
        .background(
            palette.surfaceRaised,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct IntroMark: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appear = false

    var body: some View {
        ZStack {
            Circle()
                .fill(palette.accent.opacity(0.1))
                .frame(width: 190, height: 190)
                .scaleEffect(appear ? 1 : 0.8)
            Circle()
                .fill(palette.favourite.opacity(0.12))
                .frame(width: 132, height: 132)
                .offset(x: 52, y: -40)
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 54, weight: .medium))
                .foregroundStyle(palette.onAccent)
                .frame(width: 112, height: 112)
                .background(
                    palette.accent.gradient,
                    in: RoundedRectangle(cornerRadius: 30, style: .continuous)
                )
                .shadow(color: palette.accent.opacity(0.3), radius: 18, y: 8)
        }
        .frame(height: 200)
        .onAppear {
            guard !reduceMotion else {
                appear = true
                return
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) { appear = true }
        }
        .accessibilityHidden(true)
    }
}

private struct IntroBackdrop: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            palette.background
            Circle()
                .fill(palette.accent.opacity(0.14))
                .frame(width: 340, height: 340)
                .blur(radius: 70)
                .offset(x: drift ? 140 : -120, y: drift ? -230 : -150)
            Circle()
                .fill(palette.favourite.opacity(0.1))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: drift ? -150 : 130, y: drift ? 260 : 190)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
        .accessibilityHidden(true)
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
                    Text("Activities", comment: "Sidebar item")
                } icon: {
                    Image(
                        systemName: selectedRoute == .notifications
                            ? AlohaSymbol.notificationsFilled : AlohaSymbol.notifications)
                }
                .badge(unreadActivities > 0 ? Text(verbatim: String(unreadActivities)) : nil)
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
                if session.capabilities.collections {
                    row(
                        "Albums", symbol: "rectangle.stack", route: .collections(accountID: nil),
                        comment: "Sidebar item")
                }
            } header: {
                // "Explore" was wrong over these: Discover is already in the
                // top group, and this section is lists and albums —
                // the things a person gathers, not where they stumble on new
                // ones.
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
