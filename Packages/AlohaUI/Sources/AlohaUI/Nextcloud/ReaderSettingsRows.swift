// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The one thing to do when the server says this Nextcloud user has not set up
/// their Aloha Social account: choose a username, in the web interface. The
/// app cannot do it — the server deliberately asks in a browser — so it says
/// so, and opens the page (`AccountNotSetUpException`).
struct AccountSetupBanner: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.openURL) private var openURL

    let session: AccountSession

    private var destination: URL? {
        session.accountSetupURL ?? URL(string: session.capabilities.apiBase.originString)
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                Label {
                    Text("Finish setting up your account", comment: "Account setup banner title")
                        .font(.headline)
                } icon: {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .foregroundStyle(palette.accent)
                }
                Text(
                    "Your Nextcloud account is signed in, but Aloha Social needs you to choose a username first. It takes a moment, in a web browser.",
                    comment: "Account setup banner detail"
                )
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)
                if let destination {
                    Button {
                        openURL(destination)
                    } label: {
                        Text("Open in browser", comment: "Account setup action")
                    }
                    .alohaGlassProminentButtonStyle()
                }
            }
            .padding(.vertical, AlohaMetrics.space1)
        }
    }
}

/// "Hide posts made with AI", which the server applies to every answer it
/// gives this reader (`FilterService::apply`), in every context at once.
struct AIContentFilterRow: View {
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession

    /// `nil` until the server has said; the switch is not drawn before,
    /// because a guessed position would be a switch that lies.
    @State private var hides: Bool?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let hides {
                Toggle(
                    isOn: Binding(
                        get: { hides },
                        set: { value in Task { await save(value) } })
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label {
                            Text("Hide posts made with AI", comment: "Settings item")
                        } icon: {
                            Image(systemName: "wand.and.sparkles")
                        }
                        Text(
                            "Posts that say they were made with AI, by a hashtag or by their pictures, are left out of every timeline.",
                            comment: "AI content filter explanation"
                        )
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryLabel)
                    }
                }
                .disabled(isSaving)
            } else if let errorMessage {
                Label(errorMessage, systemImage: AlohaSymbol.warning)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            hides = try await session.client.decode(
                HideSetting.self, from: .readerSettings.aiContent
            ).hide
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func save(_ value: Bool) async {
        let previous = hides
        hides = value
        isSaving = true
        defer { isSaving = false }
        do {
            hides = try await session.client.decode(
                HideSetting.self, from: .readerSettings.setAIContent(hide: value)
            ).hide
        } catch {
            hides = previous
            await session.handle(error)
        }
    }
}

/// Bluesky's two rows in Settings, drawn only once the server has said it
/// reads Bluesky for this account. A reader on a server without it never sees
/// a feature they cannot use.
struct BlueskySettingsRows: View {
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession

    var body: some View {
        Group {
            switch session.bluesky {
            case .available:
                NavigationLink(value: Route.blueskyFeeds) {
                    Label {
                        Text("Bluesky feeds", comment: "Settings item")
                    } icon: {
                        Image(systemName: "rectangle.stack.badge.person.crop")
                    }
                }
                NavigationLink(value: Route.blueskySettings) {
                    Label {
                        Text("Bluesky", comment: "Settings item")
                    } icon: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                }
            case .accountNotSetUp(let setupURL):
                // The server reads Bluesky; this account is one step short.
                if let setupURL {
                    Link(destination: setupURL) {
                        Label {
                            Text(
                                "Finish setting up your account to use Bluesky",
                                comment: "Settings item, account not set up")
                        } icon: {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                    }
                }
            case .needsNextcloudConnection, .off, .unknown:
                EmptyView()
            }
        }
        .task { await session.refreshBlueskyAvailability() }
    }
}
