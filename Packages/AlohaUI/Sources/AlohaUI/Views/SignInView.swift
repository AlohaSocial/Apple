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

    @State private var model: SignInModel
    /// What the introduction put in its field — or empty when the person
    /// chose to type it here. The sheet is presented by item, so this is a
    /// fresh copy for this one attempt.
    @State private var typed: String
    @FocusState private var isFieldFocused: Bool
    /// The account this attempt renews, when it is "sign in again" rather
    /// than "add account".
    private let reauthenticating: Reauthentication?
    /// The web step starts by itself once, when the server has answered; a
    /// cancelled or failed attempt waits for the person after that.
    @State private var hasStartedReauthentication = false

    /// An account already on this device whose sign-in has expired: who it
    /// is, and where it signed in.
    public struct Reauthentication: Sendable, Hashable {
        public var handle: String
        public var host: String
        public var apiBase: URL

        public init(handle: String, host: String, apiBase: URL) {
            self.handle = handle
            self.host = host
            self.apiBase = apiBase
        }
    }

    /// Opens with the introduction's address, or with the server it already
    /// probed, so the address and the discovery are not repeated.
    ///
    /// With `reauthenticating`, the sheet goes straight to the account's own
    /// server and on to its approval page: the person has told the app where
    /// they sign in once already, and an expired token is no reason to ask
    /// again. Signing in to the same account there renews it in place
    /// (`AppEnvironment.addAccount`), with its drafts and cache untouched.
    public init(
        address: String = "", outcome: ServerProbe.Outcome? = nil,
        reauthenticating: Reauthentication? = nil
    ) {
        _typed = State(initialValue: reauthenticating?.host ?? address)
        _model = State(initialValue: SignInModel(preloaded: outcome))
        self.reauthenticating = reauthenticating
    }

    public var body: some View {
        NavigationStack {
            Form {
                if let reauthenticating {
                    reauthenticationSection(reauthenticating)
                }

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
            .navigationTitle(title)
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
        .onAppear {
            if reauthenticating == nil, case .idle = model.phase { isFieldFocused = true }
        }
        .task { await startReauthenticationIfNeeded() }
        .onDisappear { WebAuthenticator.shared.cancel() }
    }

    private var title: Text {
        reauthenticating == nil
            ? Text("Add account", comment: "Sign-in screen title")
            : Text("Sign in again", comment: "Sign-in screen title when renewing an account")
    }

    /// The account's server, found where it signed in last time, and then
    /// its approval page — the same two steps a typed address and a tap on
    /// "Sign in" take, without the typing or the tap.
    private func startReauthenticationIfNeeded() async {
        guard let reauthenticating, !hasStartedReauthentication else { return }
        guard case .idle = model.phase else { return }
        hasStartedReauthentication = true
        await model.resolveKnownServer(
            apiBase: reauthenticating.apiBase, host: reauthenticating.host,
            environment: environment)
        guard case .found = model.phase else { return }
        await model.authorise(environment: environment) { dismiss() }
    }

    // MARK: - Sections

    /// Whose sign-in this is, so the approval page that follows is not a
    /// surprise — and so it is clear nothing was lost.
    private func reauthenticationSection(_ account: Reauthentication) -> some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        "Sign in as \(account.handle) to pick up where you left off.",
                        comment: "Sign-in again explanation; the argument is the account's handle")
                    Group {
                        Text(
                            "Your posts, drafts and settings are still here.",
                            comment: "Sign-in again reassurance")
                    }
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                }
            } icon: {
                Image(systemName: AlohaSymbol.warning)
                    .foregroundStyle(palette.accent)
            }
        }
    }

    private var entrySection: some View {
        Section {
            TextField(
                text: $typed,
                prompt: Text(verbatim: "cloud.example.com or @you@cloud.example.com")
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
            .onSubmit {
                guard parsedAddress != nil else { return }
                Task { await model.probe(typed, environment: environment) }
            }
            .accessibilityIdentifier("sign-in-server-field")

            if !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                parsedAddress == nil
            {
                Text(
                    "That doesn't look like a server address. Try cloud.example.com or @you@cloud.example.com.",
                    comment: "Sign-in validation"
                )
                .font(.footnote)
                .foregroundStyle(palette.destructive)
            }

            Button {
                Task { await model.probe(typed, environment: environment) }
            } label: {
                Text("Continue", comment: "Sign-in action")
            }
            // Return continues on a hardware keyboard: the sheet is a Mac
            // window, and its primary action must answer Return.
            .keyboardShortcut(.defaultAction)
            .disabled(parsedAddress == nil)
            .accessibilityIdentifier("sign-in-continue")
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

    private var parsedAddress: ServerProbe.ServerAddress? {
        ServerProbe.ServerAddress(typed: typed)
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
                ServerSummary(instance: outcome.instance)
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
                .accessibilityIdentifier("sign-in-authorise")

                // Nextcloud Social's client API cannot create an account — an
                // account there is a Nextcloud account — so there is never a
                // "Create account" button, only a way out to the server itself.
                if let url = URL(string: "https://\(outcome.instance.domain)") {
                    Link(destination: url) {
                        Text("Create an account on this server", comment: "Sign-in link")
                    }
                }

                Button {
                    model.reset()
                    isFieldFocused = true
                } label: {
                    Text("Use a different server", comment: "Sign-in action")
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

            if let setupURL = failure.setupURL {
                Link(destination: setupURL) {
                    Text("Open in browser", comment: "Account setup action")
                }
                .buttonStyle(.borderedProminent)
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
