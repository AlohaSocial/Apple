// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The introduction's connection step: enter an address or handle, find the
/// API, and show the server before the person agrees to terms and signs in.
///
/// The old last page only collected a string and opened a second sheet that
/// asked for it again. This is the whole exchange in one place, and the found
/// outcome is handed to sign-in so the address is typed and probed once.
struct WelcomeServerStep: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(AppEnvironment.self) private var environment

    @Binding var address: String
    @State private var model = SignInModel()
    @FocusState private var isAddressFocused: Bool

    let onContinue: (WelcomeSignInRequest) -> Void
    let onLater: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    header
                    state
                    help
                    laterButton
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)
                .frame(minHeight: geometry.size.height, alignment: .center)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("welcome-sign-in-content")
            .onChange(of: address) { _, _ in
                // Editing after a failed lookup should clear its error rather
                // than leave a stale explanation under a new address.
                if case .failed = model.phase { model.reset() }
            }
        }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(palette.accent)
                .frame(width: 64, height: 64)
                .background(
                    palette.accent.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .accessibilityHidden(true)

            Text("Your server, your home.", comment: "Onboarding server title")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text(
                "Enter the address where your account lives. A handle works too.",
                comment: "Onboarding server detail"
            )
            .font(.subheadline)
            .foregroundStyle(palette.secondaryLabel)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 340)
    }

    @ViewBuilder
    private var state: some View {
        switch model.phase {
        case .idle:
            entryCard
        case .failed(let failure):
            VStack(spacing: 12) {
                entryCard
                failureCard(failure)
            }
        case .probing, .authorising:
            probingCard
        case .found(let outcome):
            foundCard(outcome)
        }
    }

    // MARK: - Address

    private var entryCard: some View {
        IntroCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Server address or handle", comment: "Onboarding server field label")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.label)

                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(palette.tertiaryLabel)
                        .accessibilityHidden(true)

                    TextField(
                        String(
                            localized: "cloud.example.com or @you@cloud.example.com",
                            comment: "Onboarding server field prompt"),
                        text: $address
                    )
                    #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    #endif
                    .textContentType(.URL)
                    .textFieldStyle(.plain)
                    .focused($isAddressFocused)
                    .onSubmit(start)
                    .accessibilityLabel(Text("Server address", comment: "Onboarding server field"))

                    if !address.isEmpty {
                        Button {
                            address = ""
                            model.reset()
                            isAddressFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(palette.tertiaryLabel)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            Text("Clear", comment: "Onboarding server field action"))
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, address.isEmpty ? 12 : 4)
                .frame(minHeight: 48)
                .background(
                    palette.background,
                    in: RoundedRectangle(
                        cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous)
                        .strokeBorder(
                            addressValidation?.isError == true
                                ? palette.destructive.opacity(0.7)
                                : palette.separator.opacity(0.6),
                            lineWidth: 1)
                )

                if let validation = addressValidation {
                    Text(validation.message)
                        .font(.caption)
                        .foregroundStyle(
                            validation.isError ? palette.destructive : palette.tertiaryLabel
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer(minLength: 0)
                    IntroContinueButton(
                        title: String(localized: "Continue", comment: "Onboarding action")
                    ) {
                        start()
                    }
                    .disabled(!canStart)
                    .opacity(canStart ? 1 : 0.45)
                    .accessibilityIdentifier("welcome-server-continue")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 340)
    }

    private var probingCard: some View {
        IntroCard {
            HStack(spacing: AlohaMetrics.space3) {
                ProgressView()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Looking for the API…", comment: "Onboarding server probing")
                        .font(.subheadline.weight(.semibold))
                    if let candidate = model.currentCandidate {
                        Text(candidate)
                            .font(.caption.monospaced())
                            .foregroundStyle(palette.secondaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 340)
    }

    private func foundCard(_ outcome: ServerProbe.Outcome) -> some View {
        IntroCard {
            VStack(alignment: .leading, spacing: 14) {
                Label {
                    Text("Found your server", comment: "Onboarding server found")
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.accent)
                }

                ServerSummary(instance: outcome.instance)

                HStack(spacing: 12) {
                    Button {
                        model.reset()
                        isAddressFocused = true
                    } label: {
                        Text("Use a different server", comment: "Onboarding server action")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(palette.secondaryLabel)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    IntroContinueButton(
                        title: String(localized: "Continue", comment: "Onboarding action")
                    ) {
                        onContinue(
                            WelcomeSignInRequest(
                                address: address.trimmingCharacters(
                                    in: .whitespacesAndNewlines),
                                outcome: outcome))
                    }
                    .accessibilityIdentifier("welcome-server-continue")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 340)
    }

    private func failureCard(_ failure: SignInModel.Failure) -> some View {
        IntroCard {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("Couldn't find a server", comment: "Onboarding server failure")
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(palette.destructive)
                }

                Text(failure.message)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Button {
                        start()
                    } label: {
                        Text("Try again", comment: "Onboarding server action")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.borderless)

                    if failure.offersServerSnippet {
                        Button {
                            model.copyServerSnippet()
                        } label: {
                            Text("Copy setup instructions", comment: "Onboarding server action")
                                .font(.footnote)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(
                            text: Binding(
                                get: { model.manualBase },
                                set: { model.manualBase = $0 }),
                            prompt: Text(
                                verbatim: "https://cloud.example.com/index.php/apps/social/")
                        ) {
                            Text("API address", comment: "Onboarding advanced field")
                        }
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        #endif
                        .textFieldStyle(.roundedBorder)

                        Button {
                            Task { await model.useManualBase(environment: environment) }
                        } label: {
                            Text("Use this address", comment: "Onboarding advanced action")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.manualBase.isEmpty)
                    }
                    .padding(.top, 6)
                } label: {
                    Text("Advanced", comment: "Onboarding advanced section")
                        .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 340)
    }

    private var help: some View {
        VStack(spacing: 6) {
            Text(
                "A server is where your account lives. It can be a Nextcloud with Social, a Mastodon instance, or any server that speaks the Mastodon API.",
                comment: "Onboarding server explanation"
            )
            .font(.caption2)
            .foregroundStyle(palette.tertiaryLabel)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Text("Aloha Social has no account of its own.", comment: "Onboarding footnote")
                .font(.caption2)
                .foregroundStyle(palette.tertiaryLabel)
        }
        .frame(maxWidth: 340)
    }

    private var laterButton: some View {
        Button(action: onLater) {
            Text("I'll choose a server later", comment: "Onboarding action")
                .font(.footnote.weight(.medium))
                .foregroundStyle(palette.secondaryLabel)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("welcome-server-later")
    }

    // MARK: - Actions

    private var parsedAddress: ServerProbe.ServerAddress? {
        ServerProbe.ServerAddress(typed: address)
    }

    private var canStart: Bool {
        parsedAddress != nil
    }

    private var addressValidation: (message: String, isError: Bool)? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (
                String(
                    localized: "A domain, a full URL, or a handle.",
                    comment: "Onboarding server field hint"),
                false
            )
        }
        guard let address = ServerProbe.ServerAddress(typed: trimmed) else {
            return (
                String(
                    localized:
                        "That doesn't look like a server address. Try cloud.example.com or @you@cloud.example.com.",
                    comment: "Onboarding server validation"),
                true
            )
        }
        return (
            String(
                localized: "We'll look for the API at \(address.origin).",
                comment: "Onboarding server validation"),
            false
        )
    }

    private func start() {
        guard canStart else { return }
        // The field is about to be replaced by the probing card. Resign first
        // so the keyboard does not linger over the server card or the terms.
        isAddressFocused = false
        Task { await model.probe(address, environment: environment) }
    }
}
