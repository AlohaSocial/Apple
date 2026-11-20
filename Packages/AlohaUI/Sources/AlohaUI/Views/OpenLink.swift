// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import Foundation
import SwiftUI

/// What File ▸ Open Link… was given, before the server is asked about it.
enum OpenLinkInput: Equatable {
    /// One of the app's own `alohasocial://` links.
    case route(Route)
    /// `@name@server`, or `name@server`: a profile by its handle.
    case handle(String)
    /// A web address, which the account's server is asked to resolve into
    /// the post or the profile it is (`resolve=true`).
    case web(URL)
    case invalid

    init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self = .invalid
            return
        }
        if let url = URL(string: trimmed), url.scheme == RouteResolver.scheme {
            self = RouteResolver.route(for: url).map(Self.route) ?? .invalid
            return
        }
        // A handle has no scheme and no slash, and one @ between its two
        // halves; the leading @ is optional, as people paste both.
        let bare = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        let halves = bare.split(separator: "@", omittingEmptySubsequences: false)
        if halves.count == 2, halves.allSatisfy({ !$0.isEmpty }), !bare.contains("/"),
            !bare.contains(" ")
        {
            self = .handle(bare)
            return
        }
        // "mastodon.social/@alice/1" pasted without its scheme is an
        // https address.
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http", url.host()?.contains(".") == true
        else {
            self = .invalid
            return
        }
        self = .web(url)
    }
}

#if os(macOS)
    /// The Mac shell's own presentations: File ▸ Open Link…, Help ▸ Keyboard
    /// Shortcuts, and Account ▸ Sign Out's confirmation.
    struct MacShellPresentations: ViewModifier {
        @Environment(AppEnvironment.self) private var environment

        @Binding var isOpeningLink: Bool
        @Binding var isShowingShortcuts: Bool
        @Binding var signingOut: AccountSession?
        let session: AccountSession?
        let open: (Route) -> Void

        func body(content: Content) -> some View {
            content
                .sheet(isPresented: $isOpeningLink) {
                    if let session {
                        OpenLinkSheet(session: session, open: open)
                    }
                }
                .sheet(isPresented: $isShowingShortcuts) {
                    ShortcutHelpView()
                        .frame(minWidth: 460, idealWidth: 520, minHeight: 480, idealHeight: 600)
                }
                .alert(
                    signingOut.map {
                        Text(
                            "Sign out of \($0.snapshot.bestDisplayName)?",
                            comment: "Sign-out confirmation title")
                    } ?? Text(verbatim: ""),
                    isPresented: Binding(
                        get: { signingOut != nil }, set: { if !$0 { signingOut = nil } })
                ) {
                    Button(role: .destructive) {
                        if let id = signingOut?.id {
                            Task { await environment.removeAccount(id) }
                        }
                        signingOut = nil
                    } label: {
                        Text("Sign Out", comment: "Sign-out confirmation action")
                    }
                    Button(role: .cancel) {
                        signingOut = nil
                    } label: {
                        Text("Cancel", comment: "Sign-out confirmation action")
                    }
                } message: {
                    Text(
                        "This removes the account from this Mac. Your posts stay on the server.",
                        comment: "Sign-out explanation")
                }
        }
    }

    /// A post's or a profile's address, pasted, and opened in the app under
    /// the window's account — with that account's relationship to it and
    /// working buttons, rather than as a web page.
    private struct OpenLinkSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Environment(\.alohaPalette) private var palette

        let session: AccountSession
        let open: (Route) -> Void

        @State private var text = ""
        @State private var isResolving = false
        @State private var failure: String?

        var body: some View {
            VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
                Text("Open Link", comment: "Open Link sheet title")
                    .font(.headline)
                Text(
                    "Paste the address of a post or a profile on any server, or a handle such as @name@server.",
                    comment: "Open Link sheet explanation"
                )
                .font(.callout)
                .foregroundStyle(palette.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                TextField(
                    text: $text,
                    prompt: Text(verbatim: "https://mastodon.social/@…")
                ) {
                    Text("Address", comment: "Open Link field label")
                }
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await resolve() } }
                if let failure {
                    Text(failure)
                        .font(.callout)
                        .foregroundStyle(palette.destructive)
                }
                HStack {
                    if isResolving { ProgressView().controlSize(.small) }
                    Spacer()
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text("Cancel", comment: "Open Link sheet action")
                    }
                    .keyboardShortcut(.cancelAction)
                    Button {
                        Task { await resolve() }
                    } label: {
                        Text("Open", comment: "Open Link sheet action")
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(OpenLinkInput(text) == .invalid || isResolving)
                }
            }
            .padding(AlohaMetrics.space4)
            .frame(width: 440)
            // Not filled from the pasteboard: reading it unasked is what the
            // system's paste prompt is for, and ⌘V is one key away.
        }

        private func resolve() async {
            failure = nil
            switch OpenLinkInput(text) {
            case .invalid:
                return
            case .route(let route):
                finish(route)
            case .handle(let handle):
                finish(.handle(handle))
            case .web(let url):
                isResolving = true
                defer { isResolving = false }
                // The account's server fetches what it does not have yet, so a
                // post from anywhere opens here with working buttons.
                let results = try? await session.client.decode(
                    SearchResults.self,
                    from: Endpoint.search.search(url.absoluteString, resolve: true, limit: 1))
                if let status = results?.statuses.first {
                    finish(.thread(statusID: status.id))
                } else if let account = results?.accounts.first {
                    finish(.profile(accountID: account.id))
                } else {
                    failure = String(
                        localized:
                            "Your server could not find a post or a profile at that address.",
                        comment: "Open Link failure")
                }
            }
        }

        private func finish(_ route: Route) {
            dismiss()
            open(route)
        }
    }
#endif
