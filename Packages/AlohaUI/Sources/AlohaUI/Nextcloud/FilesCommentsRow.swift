// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Aloha Social's switch for posts made from a file in the reader's
/// Nextcloud: whether the replies to such a post are added to the file as
/// comments too, where the people working on it read them
/// (`/api/v1/social/files_comments`).
struct FilesCommentsRow: View {
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession

    /// `nil` until the server has said; a guessed switch would be one that
    /// lies.
    @State private var enabled: Bool?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let enabled {
                Toggle(
                    isOn: Binding(
                        get: { enabled },
                        set: { value in Task { await save(value) } })
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label {
                            Text("Replies as comments in Files", comment: "Settings item")
                        } icon: {
                            Image(systemName: "text.bubble")
                        }
                        Text(
                            "A reply to a post you made from a file in your Nextcloud is added to that file as a comment as well.",
                            comment: "Files comments switch explanation"
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
            enabled = try await session.client.decode(
                FilesCommentsSetting.self, from: .readerSettings.filesComments
            ).enabled
            errorMessage = nil
        } catch APIError.notFound {
            // A server without the switch: nothing to draw.
            enabled = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func save(_ value: Bool) async {
        let previous = enabled
        enabled = value
        isSaving = true
        defer { isSaving = false }
        do {
            enabled = try await session.client.decode(
                FilesCommentsSetting.self, from: .readerSettings.setFilesComments(enabled: value)
            ).enabled
            errorMessage = nil
        } catch {
            enabled = previous
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
