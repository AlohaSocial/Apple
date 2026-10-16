// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Delete your Social account and keep your Nextcloud one.
///
/// The same deletion `occ social:account:delete` does: the posts go, the
/// follows go, and a `Delete` goes out to every server that knew the account.
/// Until the server grew this route it was that command and nothing else, so
/// somebody who wanted their fediverse presence gone and their Nextcloud
/// account kept had to ask an administrator — which means explaining to a
/// colleague why (docs/11 §2).
///
/// **Typing the handle is the confirmation, and deliberately not a password.**
/// An account signed in through SSO has none to give, and asking for one would
/// have made this an administrator's job again for exactly the installations
/// that federate most.
///
/// The route is Nextcloud's rather than Mastodon's — `#[NoAdminRequired]`, so a
/// Nextcloud session and not a bearer token — which is why the screen asks for
/// the Nextcloud connection first instead of offering a button that 401s.
public struct DeleteAccountView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    private let session: AccountSession

    @State private var typed = ""
    @State private var isDeleting = false
    @State private var isConfirming = false
    @State private var errorMessage: String?

    public init(session: AccountSession) {
        self.session = session
    }

    /// What has to be typed: the handle as the account itself publishes it.
    private var handle: String { session.snapshot.qualifiedHandle }

    private var matches: Bool {
        typed.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(handle) == .orderedSame
            || typed.trimmingCharacters(in: .whitespaces)
                .caseInsensitiveCompare(
                    handle.hasPrefix("@") ? String(handle.dropFirst()) : "@\(handle)")
                == .orderedSame
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(palette.destructive)
            }

            Section {
                Text(
                    "Everything you posted here is deleted, everyone you follow is unfollowed, and every server that knew this account is told to forget it.",
                    comment: "Delete account explanation")
                Text(
                    "Your Nextcloud account is not touched. Your files, calendar and chat stay exactly as they are.",
                    comment: "Delete account explanation")
                Text("It cannot be undone.", comment: "Delete account warning")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.destructive)
            } header: {
                Text("What happens", comment: "Delete account section")
            } footer: {
                Text(
                    "The handle is held for a while so nobody else can take it the moment you let it go. A new account under a different handle can be made straight away.",
                    comment: "Delete account handle retention")
            }

            if session.hasNextcloudConnection {
                Section {
                    TextField(text: $typed, prompt: Text(verbatim: handle)) {
                        Text("Your handle", comment: "Delete account field")
                    }
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()

                    Button(role: .destructive) {
                        isConfirming = true
                    } label: {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text("Delete this Social account", comment: "Delete account action")
                        }
                    }
                    .disabled(!matches || isDeleting)
                } header: {
                    Text("Type your handle to confirm", comment: "Delete account section")
                }
            } else {
                Section {
                    Text(
                        "Deleting is a Nextcloud action rather than a fediverse one, so it needs your Nextcloud connection. Connect it in Settings and come back.",
                        comment: "Delete account needs Nextcloud"
                    )
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                }
            }
        }
        .alohaGround(palette)
        .navigationTitle(Text("Delete account", comment: "Screen title"))
        .confirmationDialog(
            Text("Delete \(handle)?", comment: "Delete account confirmation title"),
            isPresented: $isConfirming, titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await delete() }
            } label: {
                Text("Delete for good", comment: "Delete account action")
            }
        } message: {
            Text(
                "Your posts and follows go, and every server that knew you is told. This cannot be undone.",
                comment: "Delete account confirmation detail")
        }
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }

        do {
            _ = try await session.client.send(Endpoint.socialAccount.delete(confirm: handle))
            // The account is gone at the server; keeping its token, its cache
            // and its row here would be a signed-in account that 404s.
            await environment.removeAccount(session.id)
            dismiss()
        } catch APIError.unauthorised {
            errorMessage = String(
                localized:
                    "Your Nextcloud connection was refused. Reconnect it in Settings and try again.",
                comment: "Delete account unauthorised")
        } catch APIError.unprocessable(let message) {
            // The server's message names the handle to type, which is the whole
            // of the help there is.
            errorMessage =
                message.isEmpty
                ? String(
                    localized: "That is not the handle of this account.",
                    comment: "Delete account wrong handle")
                : message
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
