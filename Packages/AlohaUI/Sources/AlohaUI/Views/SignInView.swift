// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import AuthenticationServices
import SwiftUI

/// One screen, three states (docs/03 §8).
public struct SignInView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var model = SignInModel()
    @State private var typed = ""
    @FocusState private var isFieldFocused: Bool

    /// Opens with an address already in the field — the one the person typed
    /// on the introduction's last page, rather than asking them to type it
    /// twice.
    public init(serverAddress: String = "") {
        _typed = State(initialValue: serverAddress)
    }

    public var body: some View {
        NavigationStack {
            Form {
                switch model.phase {
                case .idle, .failed:
                    entrySection
                case .probing:
                    probingSection
                case .found(let outcome):
                    foundSection(outcome)
                case .authorising:
                    authorisingSection
                }

                if case .failed(let failure) = model.phase {
                    failureSection(failure)
                }
            }
            .formStyle(.grouped)
            .alohaGround(palette)
            .navigationTitle(Text("Add account", comment: "Sign-in screen title"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", comment: "Sign-in")
                    }
                }
            }
        }
        .onAppear { isFieldFocused = true }
        .onDisappear { WebAuthenticator.shared.cancel() }
    }

    // MARK: - Sections

    private var entrySection: some View {
        Section {
            // The app's own lockup above the field it belongs to: the screen
            // the person lands on after the introduction should look like the
            // app the introduction just showed them, not a bare form. It lives
            // inside this section's builder, because a view builder is what
            // this is — a second `Section` here would be a second expression
            // in a function whose result is one view.
            VStack(spacing: AlohaMetrics.space2) {
                AlohaLogoMark(size: 56)
                AlohaWordmark()
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, AlohaMetrics.space2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Aloha Social", comment: "App name"))

            TextField(
                text: $typed,
                prompt: Text(verbatim: "cloud.example.com")
            ) {
                Text("Your server", comment: "Sign-in field label")
            }
            .focused($isFieldFocused)
            .textContentType(.URL)
            .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            #endif
            .onSubmit { Task { await model.probe(typed, environment: environment) } }

            Button {
                Task { await model.probe(typed, environment: environment) }
            } label: {
                Text("Continue", comment: "Sign-in action")
            }
            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
        } footer: {
            VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                Text(
                    "Aloha Social works with Nextcloud Social, Mastodon, and any server that speaks the Mastodon API.",
                    comment: "Sign-in explanation")
                Link(destination: URL(string: "https://github.com/AlohaSocial/social")!) {
                    Text("What is Nextcloud Social?", comment: "Sign-in link")
                }
            }
        }
    }

    /// Honest about what is happening, which is what makes the ten-second
    /// budget feel intentional rather than slow.
    private var probingSection: some View {
        Section {
            HStack(spacing: AlohaMetrics.space3) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Looking for the API…", comment: "Sign-in probing state")
                        .font(.subheadline)
                    if let candidate = model.currentCandidate {
                        Text(candidate)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryLabel)
                    }
                }
            }
        }
    }

    private func foundSection(_ outcome: ServerProbe.Outcome) -> some View {
        Group {
            Section {
                HStack(spacing: AlohaMetrics.space3) {
                    RemoteImage(url: outcome.instance.thumbnail)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(outcome.instance.title).font(.headline)
                        Text(outcome.instance.domain)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryLabel)
                        if let users = outcome.instance.userCount {
                            Text(
                                "^[\(users) person](inflect: true)", comment: "Instance user count"
                            )
                            .font(.caption)
                            .foregroundStyle(palette.tertiaryLabel)
                        }
                    }
                }

                if !outcome.instance.shortDescription.isEmpty {
                    Text(outcome.instance.shortDescription).font(.footnote)
                }
            }

            if !outcome.instance.rules.isEmpty {
                Section {
                    ForEach(outcome.instance.rules) { rule in
                        Text(rule.text).font(.footnote)
                    }
                } header: {
                    Text("Server rules", comment: "Sign-in section header")
                }
            }

            Section {
                Button {
                    Task { await model.authorise(environment: environment) { dismiss() } }
                } label: {
                    Text("Sign in", comment: "Sign-in action")
                }

                // Nextcloud Social's client API cannot create an account — an
                // account there is a Nextcloud account — so there is never a
                // "Create account" button, only a way out to the server itself.
                if let url = URL(string: "https://\(outcome.instance.domain)") {
                    Link(destination: url) {
                        Text("Create an account on this server", comment: "Sign-in link")
                    }
                }
            } footer: {
                if outcome.winningCandidate.rank > 1 {
                    Text(
                        "Found at \(outcome.winningCandidate.explanation).",
                        comment: "Which candidate answered")
                }
            }
        }
    }

    private var authorisingSection: some View {
        Section {
            HStack(spacing: AlohaMetrics.space3) {
                ProgressView()
                Text("Waiting for your server…", comment: "Sign-in authorising state")
            }
        } footer: {
            // Where the built-in sheet could not present, the approval opened
            // in the browser instead — saying so stops this looking stuck.
            Text(
                "If approval opened in your browser, finish there and you'll come straight back.",
                comment: "Sign-in browser fallback hint")
        }
    }

    /// A genuine outcome for a self-hoster, and it must not read like a crash.
    private func failureSection(_ failure: SignInModel.Failure) -> some View {
        Section {
            Text(failure.message)
                .font(.footnote)
                .foregroundStyle(palette.destructive)

            if !failure.attempted.isEmpty {
                DisclosureGroup {
                    ForEach(failure.attempted) { candidate in
                        Text(candidate.base.absoluteString)
                            .font(.caption.monospaced())
                            .foregroundStyle(palette.secondaryLabel)
                    }
                } label: {
                    Text("What was tried", comment: "Sign-in failure detail")
                        .font(.footnote)
                }
            }

            Button {
                Task { await model.probe(typed, environment: environment) }
            } label: {
                Text("Try again", comment: "Sign-in failure action")
            }

            if failure.offersServerSnippet {
                Button {
                    model.copyServerSnippet()
                } label: {
                    Text("Copy server setup instructions", comment: "Sign-in failure action")
                }
            }

            DisclosureGroup {
                TextField(
                    text: $model.manualBase,
                    prompt: Text(verbatim: "https://cloud.example.com/index.php/apps/social/")
                ) {
                    Text("API address", comment: "Advanced sign-in field")
                }
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif

                Button {
                    Task { await model.useManualBase(environment: environment) }
                } label: {
                    Text("Use this address", comment: "Advanced sign-in action")
                }
                .disabled(model.manualBase.isEmpty)
            } label: {
                Text("Advanced", comment: "Sign-in advanced section")
                    .font(.footnote)
            }
        }
    }
}
