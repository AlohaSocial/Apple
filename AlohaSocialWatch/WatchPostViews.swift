// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import SwiftUI

/// A status body as the watch draws it: the app's own parser, so emphasis,
/// links, mentions and line breaks read as they do on the phone rather than
/// as tags stripped to spaces.
enum WatchText {
    private static let parser = StatusHTMLParser()

    static func body(of status: Status) -> AttributedString {
        let target = status.displayed
        return parser.parse(
            target.content, mentions: target.mentions, tags: target.tags, emojis: target.emojis
        ).attributedString
    }

    /// The content warning, trimmed; empty where the post has none.
    static func warning(of status: Status) -> String {
        status.displayed.spoilerText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The pictures a post can show on the wrist. Video is the phone's: only
    /// still images, and only their small previews (docs/09 §4).
    static func images(of status: Status) -> [MediaAttachment] {
        status.displayed.mediaAttachments.filter { $0.type == .image && $0.previewURL != nil }
    }
}

/// A content warning, said instead of the post. The complications already
/// show the warning rather than the text (docs/09 §4); a list row now does
/// the same, so a post is never read in full before its warning.
struct WatchWarningLabel: View {
    let warning: String

    var body: some View {
        Label {
            Text(verbatim: warning)
        } icon: {
            Image(systemName: AlohaSymbol.warning)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.orange)
    }
}

/// One post in a list: who wrote it, then its warning or its first lines,
/// and a thumbnail where it has a picture that may be shown.
struct WatchPostRow: View {
    let status: Status
    /// Who to name above the post, where it is not the author — a mention's
    /// sender is, but a notification row names the account it is about.
    var title: String?

    var body: some View {
        let warning = WatchText.warning(of: status)
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title ?? status.displayed.account.bestDisplayName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                if warning.isEmpty {
                    Text(WatchText.body(of: status))
                        .font(.caption2)
                        .lineLimit(3)
                } else {
                    WatchWarningLabel(warning: warning)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            // Behind a warning, or marked sensitive, a picture waits for the
            // post to be opened and revealed; a row never shows it.
            if warning.isEmpty, !status.displayed.sensitive,
                let first = WatchText.images(of: status).first
            {
                WatchThumbnail(attachment: first)
                    .frame(width: 34, height: 34)
            }
        }
    }
}

/// A picture's small preview, cropped to a square.
struct WatchThumbnail: View {
    let attachment: MediaAttachment

    var body: some View {
        AsyncImage(url: attachment.previewURL) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(.quaternary)
        }
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityLabel(
            attachment.description.map { Text(verbatim: $0) }
                ?? Text("Image", comment: "Watch, a picture without a description"))
    }
}

/// A post's words and pictures on its own screen. Behind a content warning
/// they wait for a tap, as they do on the phone; a sensitive picture without
/// a warning is blurred until tapped.
struct WatchPostBody: View {
    let status: Status

    @State private var isRevealed = false
    @State private var isMediaRevealed = false

    var body: some View {
        let warning = WatchText.warning(of: status)
        VStack(alignment: .leading, spacing: 8) {
            if warning.isEmpty {
                content(blursMedia: status.displayed.sensitive && !isMediaRevealed)
            } else {
                WatchWarningLabel(warning: warning)
                Button {
                    withAnimation { isRevealed.toggle() }
                } label: {
                    if isRevealed {
                        Text("Hide post", comment: "Watch, hide a post behind its content warning")
                    } else {
                        Text(
                            "Show post", comment: "Watch, reveal a post behind its content warning")
                    }
                }
                .buttonStyle(.bordered)
                // Revealing the warning reveals the whole post, pictures too:
                // the warning was the one question asked.
                if isRevealed { content(blursMedia: false) }
            }
        }
    }

    @ViewBuilder
    private func content(blursMedia: Bool) -> some View {
        Text(WatchText.body(of: status))
            .font(.caption2)
        let images = WatchText.images(of: status)
        if !images.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(images) { image in
                        WatchThumbnail(attachment: image)
                            .frame(width: 72, height: 72)
                            .blur(radius: blursMedia ? 12 : 0)
                    }
                }
            }
            .overlay {
                if blursMedia {
                    Button {
                        withAnimation { isMediaRevealed = true }
                    } label: {
                        Label {
                            Text("Sensitive", comment: "Watch, reveal sensitive pictures")
                        } icon: {
                            Image(systemName: AlohaSymbol.sensitive)
                        }
                        .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

/// Under a list showing what the watch last saw, because the server could
/// not be reached: how old it is.
struct WatchUpdatedHint: View {
    let updatedAt: Date?

    var body: some View {
        TimelineView(.everyMinute) { context in
            Label {
                if let updatedAt {
                    Text(
                        "Updated \(updatedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))",
                        comment:
                            "Watch, under a list it could not refresh; the value is like “5 min. ago”"
                    )
                } else {
                    Text("Couldn't connect", comment: "Watch, a list that never loaded")
                }
            } icon: {
                Image(systemName: AlohaSymbol.offline)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .id(context.date)
        }
    }
}
