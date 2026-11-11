// SPDX-License-Identifier: MIT

import AlohaDesign
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

public struct WelcomeView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let onAddAccount: (WelcomeSignInRequest?) -> Void
    private let showsConnectionStep: Bool

    @State private var page = 0
    @State private var serverAddress = ""

    private var pageCount: Int { showsConnectionStep ? 8 : 7 }

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
                    case 0: heroPage
                    case 1: welcomePage
                    case 2: feedsPage
                    case 3: actionsPage
                    case 4: photosPage
                    case 5: storiesPage
                    case 6: quietPage
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

                if page < pageCount - 1 {
                    Button {
                        go(to: pageCount - 1)
                    } label: {
                        Text("Skip", comment: "Onboarding action")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(palette.label)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 5) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? palette.accent : palette.separator.opacity(0.55))
                        .frame(width: index == page ? 18 : 5, height: 5)
                        .animation(.easeInOut(duration: 0.2), value: page)
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

                if page < pageCount - 1 {
                    IntroContinueButton(
                        title: String(localized: "Continue", comment: "Onboarding action")
                    ) {
                        go(to: page + 1)
                    }
                }
            }
            .frame(height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    // MARK: - Pages

    private var heroPage: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 0)

                    AlohaLogo()

                    VStack(spacing: 8) {
                        Text("A calmer client for the social web.", comment: "Onboarding title")
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text("Your server. Your people. Your feed.", comment: "Onboarding detail")
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryLabel)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 340)

                    Spacer(minLength: 0)
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

    private var welcomePage: some View {
        IntroPage(
            title: String(
                localized: "Your feed, without the noise.",
                comment: "Onboarding title"),
            detail: String(
                localized: "Posts, photos, videos and stories from the people you follow.",
                comment: "Onboarding detail")
        ) {
            WelcomeMockup()
        }
    }

    private var feedsPage: some View {
        IntroPage(
            title: String(
                localized: "Six feeds, each its own screen.", comment: "Onboarding title"),
            detail: String(
                localized: "Tap along the tab bar to preview each one.",
                comment: "Onboarding detail")
        ) {
            FeedsMockup()
        }
    }

    private var actionsPage: some View {
        IntroPage(
            title: String(
                localized: "The same four actions, everywhere.",
                comment: "Onboarding title"),
            detail: String(
                localized: "Like, repost, reply and save keep their order. Tap to try.",
                comment: "Onboarding detail")
        ) {
            ActionsMockup()
        }
    }

    private var photosPage: some View {
        IntroPage(
            title: String(
                localized: "Photos, without the noise.", comment: "Onboarding title"),
            detail: String(
                localized: "A grid that opens into full posts. Double-tap a photo to like it.",
                comment: "Onboarding detail")
        ) {
            PhotosMockup()
        }
    }

    private var storiesPage: some View {
        IntroPage(
            title: String(
                localized: "Stories that start in the camera.", comment: "Onboarding title"),
            detail: String(
                localized: "Shoot, crop, add a sticker, share. The canvas is the story.",
                comment: "Onboarding detail")
        ) {
            StoriesMockup()
        }
    }

    private var quietPage: some View {
        IntroPage(
            title: String(localized: "Quiet by default.", comment: "Onboarding title"),
            detail: String(
                localized: "Sensitive media stays covered. Numbers appear only when you ask.",
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

private struct WelcomeMockup: View {
    @Environment(\.alohaPalette) private var palette

    var body: some View {
        IntroCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(palette.accent.opacity(0.25))
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Capsule().fill(palette.label.opacity(0.25)).frame(width: 48, height: 4)
                        Capsule().fill(palette.separator).frame(width: 32, height: 3)
                    }
                    Spacer()
                    Image(systemName: AlohaSymbol.more)
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryLabel)
                }

                HStack(spacing: 7) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index == 0 ? palette.accent.opacity(0.25) : palette.background)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle().strokeBorder(
                                    index == 0 ? palette.accent : palette.separator,
                                    lineWidth: index == 0 ? 2 : 0.5))
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(palette.label.opacity(0.22)).frame(width: 92, height: 5)
                    Capsule().fill(palette.separator).frame(width: 128, height: 4)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    palette.accent.opacity(0.55), palette.favourite.opacity(0.4),
                                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(height: 82)
                    HStack(spacing: 14) {
                        Image(systemName: AlohaSymbol.favourite)
                            .foregroundStyle(palette.favourite)
                        Image(systemName: AlohaSymbol.boost)
                            .foregroundStyle(palette.boost)
                        Image(systemName: AlohaSymbol.reply)
                            .foregroundStyle(palette.secondaryLabel)
                        Spacer()
                        Image(systemName: AlohaSymbol.bookmark)
                            .foregroundStyle(palette.bookmark)
                    }
                    .font(.caption)
                }
                .padding(9)
                .background(
                    palette.background.opacity(0.65),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 18) {
                    Image(systemName: FeedMode.home.symbolName)
                    Image(systemName: FeedMode.photos.symbolName)
                    Image(systemName: FeedMode.video.symbolName)
                    Image(systemName: FeedMode.news.symbolName)
                    Spacer()
                    Image(systemName: "person.crop.circle")
                }
                .font(.caption2)
                .foregroundStyle(palette.tertiaryLabel)
                .padding(.horizontal, 8)
            }
            .frame(width: 212)
        }
    }
}

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

private struct ActionsMockup: View {
    @Environment(\.alohaPalette) private var palette
    @State private var liked = false
    @State private var boosted = false
    @State private var saved = false
    @State private var replying = false

    var body: some View {
        IntroCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(palette.accent.opacity(0.22))
                        .frame(width: 20, height: 20)
                    Text("Mira", comment: "Onboarding mock author")
                        .font(.caption.weight(.semibold))
                    Text("now", comment: "Onboarding mock time")
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryLabel)
                    Spacer()
                    Image(systemName: AlohaSymbol.more)
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryLabel)
                }

                Text("A quieter way to keep up.", comment: "Onboarding mock post")
                    .font(.subheadline)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.favourite.opacity(0.45), palette.accent.opacity(0.35),
                            ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(height: 84)

                HStack(spacing: 0) {
                    actionButton(
                        AlohaSymbol.favourite, count: liked ? 13 : 12, tint: palette.favourite,
                        isOn: liked,
                        label: String(localized: "Favourite", comment: "Status action")
                    ) { liked.toggle() }
                    actionButton(
                        AlohaSymbol.boost, count: boosted ? 5 : 4, tint: palette.boost,
                        isOn: boosted,
                        label: String(localized: "Boost", comment: "Status action")
                    ) { boosted.toggle() }
                    actionButton(
                        AlohaSymbol.reply, count: 3, tint: palette.accent, isOn: replying,
                        label: String(localized: "Reply", comment: "Status action")
                    ) { replying.toggle() }
                    actionButton(
                        saved ? AlohaSymbol.bookmarkFilled : AlohaSymbol.bookmark, count: nil,
                        tint: palette.bookmark, isOn: saved,
                        label: String(localized: "Bookmark", comment: "Status action")
                    ) { saved.toggle() }
                }
                .animation(.easeInOut(duration: 0.2), value: liked)
                .animation(.easeInOut(duration: 0.2), value: boosted)
                .animation(.easeInOut(duration: 0.2), value: saved)

                if replying {
                    Text("Reply…", comment: "Onboarding mock reply")
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryLabel)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            palette.background.opacity(0.65),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(width: 280)
            .animation(.easeInOut(duration: 0.2), value: replying)
        }
    }

    private func actionButton(
        _ symbol: String, count: Int?, tint: Color, isOn: Bool, label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                if let count {
                    Text(verbatim: "\(count)").monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(isOn ? tint : palette.secondaryLabel)
            .frame(maxWidth: .infinity, minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

private struct PhotosMockup: View {
    @Environment(\.alohaPalette) private var palette
    @State private var liked = false

    var body: some View {
        IntroCard {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.18, green: 0.52, blue: 0.82),
                                    Color(red: 0.55, green: 0.30, blue: 0.72),
                                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(height: 180)

                    if liked {
                        Image(systemName: AlohaSymbol.favouriteFilled)
                            .font(.system(size: 50))
                            .foregroundStyle(.white)
                            .shadow(radius: 8)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }

                    VStack {
                        Spacer()
                        HStack {
                            Label {
                                Text("Lake", comment: "Onboarding mock place")
                            } icon: {
                                Image(systemName: "mappin.and.ellipse")
                            }
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.3), in: Capsule())
                            Spacer()
                        }
                    }
                    .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                        liked.toggle()
                    }
                }
                .accessibilityAction(
                    named: Text("Like or unlike", comment: "Onboarding mock action")
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                        liked.toggle()
                    }
                }

                HStack {
                    Text("Double-tap the photo", comment: "Onboarding mock hint")
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryLabel)
                    Spacer()
                    HStack(spacing: 3) {
                        Image(
                            systemName: liked
                                ? AlohaSymbol.favouriteFilled : AlohaSymbol.favourite)
                        Text(verbatim: liked ? "25" : "24").monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(liked ? palette.favourite : palette.secondaryLabel)
                }
            }
            .frame(width: 260)
        }
    }
}

private struct StoriesMockup: View {
    @Environment(\.alohaPalette) private var palette
    @State private var showsGrid = true
    @State private var showsSticker = false
    @State private var showsText = false

    var body: some View {
        IntroCard {
            VStack(spacing: 8) {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.50, blue: 0.30),
                            Color(red: 0.75, green: 0.25, blue: 0.55),
                        ], startPoint: .top, endPoint: .bottom)

                    if showsGrid {
                        IntroCropGrid()
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                    }

                    if showsSticker {
                        Text("🌺", comment: "Onboarding mock story sticker")
                            .font(.system(size: 28))
                            .offset(x: 40, y: -60)
                    }

                    if showsText {
                        Text("Hello", comment: "Onboarding mock story text")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.35), in: Capsule())
                            .offset(y: 78)
                    }

                    VStack {
                        Spacer()
                        Circle()
                            .strokeBorder(.white, lineWidth: 2.5)
                            .frame(width: 30, height: 30)
                            .padding(.bottom, 8)
                    }
                }
                .frame(width: 170, height: 284)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: 6) {
                    chip(
                        String(localized: "Crop", comment: "Onboarding story tool"),
                        symbol: "crop", isOn: showsGrid
                    ) { showsGrid.toggle() }
                    chip(
                        String(localized: "Sticker", comment: "Onboarding story tool"),
                        symbol: "face.smiling", isOn: showsSticker
                    ) { showsSticker.toggle() }
                    chip(
                        String(localized: "Text", comment: "Onboarding story tool"),
                        symbol: "textformat", isOn: showsText
                    ) { showsText.toggle() }
                }
            }
            .frame(width: 190)
        }
    }

    private func chip(
        _ title: String, symbol: String, isOn: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title).font(.caption2.weight(.medium))
            } icon: {
                Image(systemName: symbol).font(.caption2)
            }
            .foregroundStyle(isOn ? palette.onAccent : palette.secondaryLabel)
            .padding(.horizontal, 7)
            .frame(height: 28)
            .background(
                isOn ? palette.accent : palette.background.opacity(0.65), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
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
                        Text("Show numbers", comment: "Onboarding demo toggle")
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

private struct IntroCropGrid: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction in [1.0 / 3.0, 2.0 / 3.0] {
            let x = rect.width * fraction
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            let y = rect.height * fraction
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
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
