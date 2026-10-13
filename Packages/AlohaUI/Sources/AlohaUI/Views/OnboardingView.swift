// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// Shown before any content, as Guideline 1.2 requires for an app that displays
/// user-generated content from servers it does not control (docs/11 §1.5).
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
        Form {
            Section {
                Text(
                    "Aloha Social shows posts from servers across the fediverse. Those servers are run by other people, and this app does not control what they publish.",
                    comment: "Terms gate explanation")
            } header: {
                Text("Before you start", comment: "Terms gate title")
            }

            Section {
                rule(
                    symbol: AlohaSymbol.block,
                    text: String(
                        localized:
                            "There is zero tolerance for objectionable content and abusive behaviour.",
                        comment: "Terms rule"))
                rule(
                    symbol: AlohaSymbol.report,
                    text: String(
                        localized:
                            "You can report any post or account, and block or mute anyone, from anywhere in the app.",
                        comment: "Terms rule"))
                rule(
                    symbol: AlohaSymbol.sensitive,
                    text: String(
                        localized:
                            "Reports go to your server's moderators, and optionally to the poster's server too.",
                        comment: "Terms rule"))
                rule(
                    symbol: "hand.raised.slash",
                    text: String(
                        localized:
                            "Accounts that abuse other people are removed from your view as soon as you block them.",
                        comment: "Terms rule"))
            }

            Section {
                Text(
                    "By continuing you agree to use Aloha Social without posting or promoting objectionable content, and to accept that other people's servers set their own rules.",
                    comment: "Terms agreement"
                )
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)
            }

            Section {
                Button {
                    Self.recordAcceptance()
                    onAccept()
                } label: {
                    Text("Agree and continue", comment: "Terms action")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                // Return agrees on a hardware keyboard: the terms sheet is a
                // Mac window, and its primary action must answer Return.
                .keyboardShortcut(.defaultAction)

                Button(role: .cancel, action: onDecline) {
                    Text("Not now", comment: "Terms action")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
            }
        }
        .formStyle(.grouped)
        .alohaGround(palette)
    }

    private func rule(symbol: String, text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(palette.accent)
        }
    }
}

/// What a person sees after agreeing and before adding an account.
public struct ModeSelectionView: View {
    @Environment(\.alohaPalette) private var palette

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
        List {
            Section {
                ForEach(FeedMode.allCases.filter { capabilities.supports($0) }) { mode in
                    Button {
                        if selected.contains(mode) {
                            selected.remove(mode)
                        } else {
                            selected.insert(mode)
                        }
                    } label: {
                        HStack(spacing: AlohaMetrics.space3) {
                            Image(systemName: mode.symbolName)
                                .frame(width: 28)
                                .foregroundStyle(palette.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(mode))
                                    .font(.body)
                                    .foregroundStyle(palette.label)
                                Text(detail(mode))
                                    .font(.caption)
                                    .foregroundStyle(palette.secondaryLabel)
                            }
                            Spacer()
                            if selected.contains(mode) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(palette.accent)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        Text("\(title(mode)), \(selected.contains(mode) ? "on" : "off")"))
                }
            } header: {
                Text("Which feeds do you want?", comment: "Mode selection title")
            } footer: {
                Text(
                    "Each one is its own screen, built for what it shows. You can change these later in Settings.",
                    comment: "Mode selection explanation"
                )
            }

            Section {
                Button(action: onContinue) {
                    Text("Continue", comment: "Mode selection action")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
            .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .alohaGround(palette)
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
