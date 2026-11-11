// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// Shown before any content, as Guideline 1.2 requires for an app that displays
/// user-generated content from servers it does not control (docs/11 §1.5).
///
/// A form of four paragraphs read as paperwork. The rules are cards, each one
/// a promise with a glyph beside it, and the agreement is a button at the end
/// of the same column rather than a section of a form.
public struct TermsGate: View {
    @Environment(\.alohaPalette) private var palette

    public static let currentVersion = 1
    private static let acceptedKey = "aloha.acceptedTermsVersion"

    private let onAccept: () -> Void
    private let onDecline: () -> Void

    public init(onAccept: @escaping () -> Void, onDecline: @escaping () -> Void) {
        self.onAccept = onAccept
        self.onDecline = onDecline
    }

    public static var hasAccepted: Bool {
        UserDefaults.standard.integer(forKey: acceptedKey) >= currentVersion
    }

    public static func recordAcceptance() {
        UserDefaults.standard.set(currentVersion, forKey: acceptedKey)
        UserDefaults.standard.set(Date(), forKey: "aloha.acceptedTermsAt")
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlohaMetrics.space4) {
                hero

                VStack(spacing: AlohaMetrics.space2) {
                    rule(
                        symbol: "hand.raised.slash",
                        title: Text("No abuse, ever", comment: "Terms rule title"),
                        text: Text(
                            "There is zero tolerance for objectionable content and abusive behaviour.",
                            comment: "Terms rule"))
                    rule(
                        symbol: AlohaSymbol.report,
                        title: Text("You are in control", comment: "Terms rule title"),
                        text: Text(
                            "Report any post or account, and block or mute anyone, from anywhere in the app.",
                            comment: "Terms rule"))
                    rule(
                        symbol: "checkmark.shield",
                        title: Text("Moderators, not magic", comment: "Terms rule title"),
                        text: Text(
                            "Reports go to your server's moderators, and optionally to the poster's server too.",
                            comment: "Terms rule"))
                    rule(
                        symbol: "person.crop.circle.badge.xmark",
                        title: Text("Gone means gone", comment: "Terms rule title"),
                        text: Text(
                            "Accounts that abuse other people are removed from your view as soon as you block them.",
                            comment: "Terms rule"))
                }

                Text(
                    "By continuing you agree to use Aloha Social without posting or promoting objectionable content, and to accept that other people's servers set their own rules.",
                    comment: "Terms agreement"
                )
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: AlohaMetrics.space2) {
                    Button {
                        Self.recordAcceptance()
                        onAccept()
                    } label: {
                        Text("Agree and continue", comment: "Terms action")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.alohaProminent)
                    .controlSize(.large)
                    // Return agrees on a hardware keyboard: the terms sheet is
                    // a Mac window, and its primary action must answer Return.
                    .keyboardShortcut(.defaultAction)

                    Button(role: .cancel, action: onDecline) {
                        Text("Not now", comment: "Terms action")
                            .foregroundStyle(palette.label)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.top, AlohaMetrics.space2)
            }
            .padding(AlohaMetrics.space5)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(palette.background.ignoresSafeArea())
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(palette.onAccent)
                .frame(width: 58, height: 58)
                .background(
                    LinearGradient(
                        colors: [palette.accent, palette.accentMuted],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )

            Text("Before you start", comment: "Terms gate title")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(palette.label)

            Text(
                "Aloha Social shows posts from servers across the fediverse. Those servers are run by other people, and this app does not control what they publish.",
                comment: "Terms gate explanation"
            )
            .font(.body)
            .foregroundStyle(palette.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func rule(symbol: String, title: Text, text: Text) -> some View {
        HStack(alignment: .top, spacing: AlohaMetrics.space3) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(palette.accent)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.label)
                text
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(AlohaMetrics.space3)
        .background(
            palette.surfaceRaised,
            in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
        )
    }
}

/// What a person sees after agreeing and before adding an account.
///
/// The feeds are cards that light up when chosen, not switches in a form: this
/// is the one screen where the app explains what it is, and it should feel
/// like choosing what to read rather than filling in settings.
public struct ModeSelectionView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding private var selected: Set<FeedMode>
    private let capabilities: ServerCapabilities
    private let onContinue: () -> Void

    public init(
        selected: Binding<Set<FeedMode>>, capabilities: ServerCapabilities,
        onContinue: @escaping () -> Void
    ) {
        _selected = selected
        self.capabilities = capabilities
        self.onContinue = onContinue
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlohaMetrics.space4) {
                VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                    Text("Which feeds do you want?", comment: "Mode selection title")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(palette.label)
                    Text(
                        "Each one is its own screen, built for what it shows. You can change these later in Settings.",
                        comment: "Mode selection explanation"
                    )
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: AlohaMetrics.space2) {
                    ForEach(FeedMode.offered.filter { capabilities.supports($0) }) { mode in
                        modeCard(mode)
                    }
                }

                Button(action: onContinue) {
                    Text("Continue", comment: "Mode selection action")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.alohaProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
                .padding(.top, AlohaMetrics.space2)
            }
            .padding(AlohaMetrics.space5)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(palette.background.ignoresSafeArea())
    }

    private func modeCard(_ mode: FeedMode) -> some View {
        let isOn = selected.contains(mode)
        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                if isOn {
                    selected.remove(mode)
                } else {
                    selected.insert(mode)
                }
            }
        } label: {
            HStack(spacing: AlohaMetrics.space3) {
                Image(systemName: mode.symbolName)
                    .font(.title3)
                    .foregroundStyle(isOn ? palette.onAccent : palette.accent)
                    .frame(width: 44, height: 44)
                    .background(
                        isOn ? palette.accent : palette.accent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title(mode))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(palette.label)
                    Text(detail(mode))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                }

                Spacer(minLength: 0)

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? palette.accent : palette.tertiaryLabel)
                    .accessibilityHidden(true)
            }
            .padding(AlohaMetrics.space3)
            .background(
                palette.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
                    .strokeBorder(
                        isOn ? palette.accent : palette.separator, lineWidth: isOn ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(
                "\(title(mode)), \(isOn ? "on" : "off")",
                comment: "Accessibility label for a feed mode switch")
        )
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private func title(_ mode: FeedMode) -> String {
        switch mode {
        case .home: String(localized: "Home", comment: "Mode title")
        case .photos: String(localized: "Photos", comment: "Mode title")
        case .video: String(localized: "Video", comment: "Mode title")
        case .shorts: String(localized: "Shorts", comment: "Mode title")
        case .news: String(localized: "News", comment: "Mode title")
        case .audio: String(localized: "Audio", comment: "Mode title")
        }
    }

    private func detail(_ mode: FeedMode) -> String {
        switch mode {
        case .home: String(localized: "Everything, in order", comment: "Mode detail")
        case .photos: String(localized: "A grid of pictures", comment: "Mode detail")
        case .video:
            String(localized: "Long-form video, with where you got to", comment: "Mode detail")
        case .shorts: String(localized: "Short vertical clips, full screen", comment: "Mode detail")
        case .news: String(localized: "Links and articles", comment: "Mode detail")
        case .audio: String(localized: "Audio, with background playback", comment: "Mode detail")
        }
    }
}
