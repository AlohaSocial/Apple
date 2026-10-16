// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

// Two of Aloha Social's own safety settings, drawn in Privacy & Safety beside
// blocks and mutes: who may start a conversation with the reader, and the
// shared mute and block lists they subscribe to.

/// Who may send the reader a direct message (`/api/v1/social/direct_messages`).
struct DirectMessageAudienceSection: View {
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession

    /// `nil` until the server has said, so the picker never shows a guess.
    @State private var audience: DirectMessageAudience?
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if let audience {
                Picker(
                    selection: Binding(
                        get: { audience },
                        set: { value in Task { await save(value) } })
                ) {
                    Text("Everybody", comment: "Who may message you").tag(DirectMessageAudience.all)
                    Text("People you follow", comment: "Who may message you")
                        .tag(DirectMessageAudience.following)
                    Text("Nobody", comment: "Who may message you").tag(DirectMessageAudience.none)
                } label: {
                    Text("Who can message you", comment: "Settings item")
                }
            } else if let errorMessage {
                Label(errorMessage, systemImage: AlohaSymbol.warning)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
            } else {
                ProgressView()
            }
        } header: {
            Text("Direct messages", comment: "Safety section")
        } footer: {
            Text(
                "A message from somebody not allowed never reaches you. Conversations you started stay open.",
                comment: "Who may message you explanation")
        }
        .task { await load() }
    }

    private func load() async {
        do {
            audience = try await session.client.decode(
                DirectMessageSetting.self, from: .readerSettings.directMessages
            ).from
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func save(_ value: DirectMessageAudience) async {
        let previous = audience
        audience = value
        do {
            audience = try await session.client.decode(
                DirectMessageSetting.self, from: .readerSettings.setDirectMessages(from: value)
            ).from
        } catch {
            audience = previous
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Bluesky's shared mute and block lists, which Aloha Social applies here
/// (`/api/v1/social/moderation_lists`). The routes need the Nextcloud app
/// password, so without one the section says where to connect instead.
struct SharedModerationListsSection: View {
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession

    @State private var lists: [ModerationList] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var newURL = ""
    @State private var newKind: ModerationList.Kind = .mute
    @State private var isSubscribing = false
    /// 404 is a server without Bluesky, which has no shared lists to offer.
    @State private var isUnavailable = false

    var body: some View {
        if !isUnavailable {
            Section {
                if !session.hasNextcloudConnection {
                    Text(
                        "Connect your Nextcloud in Settings to subscribe to shared lists.",
                        comment: "Shared lists need Nextcloud"
                    )
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                } else {
                    if let errorMessage {
                        Label(errorMessage, systemImage: AlohaSymbol.warning)
                            .font(.footnote)
                            .foregroundStyle(palette.destructive)
                    }
                    ForEach(lists) { list in
                        row(list)
                    }
                    subscribeRows
                }
            } header: {
                Text("Shared lists", comment: "Safety section")
            } footer: {
                Text(
                    "A Bluesky mute or block list, kept by somebody else. Everybody on it is muted or blocked for you, and the list stays up to date.",
                    comment: "Shared lists explanation")
            }
            .task { await load() }
        }
    }

    private func row(_ list: ModerationList) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name.isEmpty ? list.uri : list.name)
                    .lineLimit(1)
                Text(
                    list.kind == .block
                        ? "Blocks ^[\(list.accounts) account](inflect: true)"
                        : "Mutes ^[\(list.accounts) account](inflect: true)",
                    comment: "Shared list row detail"
                )
                .font(AlohaType.meta)
                .foregroundStyle(palette.secondaryLabel)
            }
            Spacer()
            Button {
                Task { await unsubscribe(list) }
            } label: {
                Text("Unsubscribe", comment: "Shared list action")
            }
            .font(.caption)
        }
    }

    @ViewBuilder private var subscribeRows: some View {
        TextField(
            text: $newURL,
            prompt: Text("bsky.app/profile/…/lists/…", comment: "Shared list address placeholder")
        ) {
            Text("List address", comment: "Shared list address field")
        }
        .textContentType(.URL)
        .autocorrectionDisabled()
        #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
        #endif

        Picker(selection: $newKind) {
            Text("Mute everybody on it", comment: "Shared list kind").tag(ModerationList.Kind.mute)
            Text("Block everybody on it", comment: "Shared list kind")
                .tag(ModerationList.Kind.block)
        } label: {
            Text("Then", comment: "Shared list kind picker")
        }

        Button {
            Task { await subscribe() }
        } label: {
            Text("Subscribe", comment: "Shared list action")
        }
        .disabled(newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubscribing)
    }

    private func load() async {
        guard session.hasNextcloudConnection else {
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            lists = try await session.client.decode(
                LossyArray<ModerationList>.self, from: .moderationLists.all
            ).elements
            errorMessage = nil
        } catch APIError.notFound {
            isUnavailable = true
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func subscribe() async {
        let url = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubscribing = true
        defer { isSubscribing = false }
        do {
            let list = try await session.client.decode(
                ModerationList.self, from: .moderationLists.subscribe(url: url, kind: newKind))
            lists.removeAll { $0.uri == list.uri }
            lists.append(list)
            newURL = ""
            errorMessage = nil
        } catch {
            await session.handle(error)
            // A list that cannot be read is a 422 saying why.
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func unsubscribe(_ list: ModerationList) async {
        let before = lists
        lists.removeAll { $0.uri == list.uri }
        do {
            try await session.client.send(.moderationLists.unsubscribe(uri: list.uri))
        } catch {
            lists = before
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
