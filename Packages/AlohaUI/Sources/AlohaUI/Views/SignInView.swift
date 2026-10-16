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
    /// Bound to the shell's `signInAddress`, not a copy of it: what the
    /// introduction's last page holds stays in the field, so the address is
    /// typed once — here or there — and never asked for twice. A `State`
    /// snapshot went stale whenever the sheet presented with an older value.
    @Binding private var typed: String
    @FocusState private var isFieldFocused: Bool

    /// Opens with an address already in the field — the one the person typed
    /// on the introduction's last page, rather than asking them to type it
    /// twice.
    public init(serverAddress: Binding<String> = .constant("")) {
        _typed = serverAddress
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
            // Return continues on a hardware keyboard: the sheet is a Mac
            // window, and its primary action must answer Return.
            .keyboardShortcut(.defaultAction)
            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            BrandMark(size: 72)
                .frame(maxWidth: .infinity)
                .padding(.bottom, AlohaMetrics.space3)
        } footer: {
            VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                Text(
                    "Aloha Social works with Nextcloud, Mastodon, and any server that speaks the Mastodon API.",
                    comment: "Sign-in explanation")
                Link(destination: URL(string: "https://nextcloud.com")!) {
                    Text("What is Nextcloud?", comment: "Sign-in link")
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
                        // What the server reports about itself: people, posts,
                        // connected servers — whichever of those this server's
                        // API generation actually serves (v2 has no post or
                        // server counts, and a missing number is omitted rather
                        // than shown as zero).
                        serverStats(outcome.instance)
                        serverDetails(outcome.instance)
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
                .keyboardShortcut(.defaultAction)

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

    /// People, posts and connected servers as one line of facts — each only
    /// where the server answered it.
    @ViewBuilder
    private func serverStats(_ instance: InstanceDescription) -> some View {
        let stats: [Text] = [
            instance.userCount.map {
                Text("^[\($0) person](inflect: true)", comment: "Instance user count")
            },
            instance.statusCount.map {
                Text("^[\($0) post](inflect: true)", comment: "Instance post count")
            },
            instance.domainCount.map {
                Text(
                    "^[\($0) connected server](inflect: true)",
                    comment: "Instance server count")
            },
        ].compactMap { $0 }
        if !stats.isEmpty {
            // One Text from many: `Text + Text` localises as a unit, and the
            // separators join without a trailing one.
            stats.dropFirst().reduce(stats[0]) { $0 + Text(verbatim: " · ") + $1 }
                .font(.caption)
                .foregroundStyle(palette.tertiaryLabel)
        }
    }

    /// Version, registration state and languages: the three things that tell
    /// a person whether this server takes new accounts and speaks theirs.
    private func serverDetails(_ instance: InstanceDescription) -> some View {
        var parts: [String] = []
        if !instance.version.isEmpty { parts.append(instance.version) }
        if instance.registrationsEnabled {
            parts.append(
                instance.approvalRequired
                    ? String(
                        localized: "Registrations open, approval required",
                        comment: "Instance detail")
                    : String(localized: "Registrations open", comment: "Instance detail"))
        } else {
            parts.append(String(localized: "Registrations closed", comment: "Instance detail"))
        }
        if !instance.languages.isEmpty {
            parts.append(instance.languages.joined(separator: ", ").uppercased())
        }
        return Text(parts.joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(palette.tertiaryLabel)
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

            if let setupURL = failure.setupURL {
                Link(destination: setupURL) {
                    Text("Open in browser", comment: "Account setup action")
                }
                .alohaGlassProminentButtonStyle()
            }

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
