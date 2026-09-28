// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import SwiftUI

/// Renders parsed status content.
///
/// Parsing happens off the main actor and is cached by content hash; a row that
/// arrives uncached shows plain text for one frame and upgrades rather than
/// blocking (docs/05 §3).
public struct RichTextView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics

    private let status: Status
    private let lineLimit: Int?
    private let isSelectable: Bool
    private let onTap: (RichText.Link) -> Void

    @State private var richText: RichText?

    public init(
        status: Status, lineLimit: Int? = nil, isSelectable: Bool = false,
        onTap: @escaping (RichText.Link) -> Void = { _ in }
    ) {
        self.status = status
        self.lineLimit = lineLimit
        self.isSelectable = isSelectable
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if let richText {
                content(richText)
            } else {
                // The one-frame fallback. Never a spinner, never empty space.
                Text(fallbackText)
                    .font(bodyFont)
                    .foregroundStyle(palette.label)
                    .lineLimit(lineLimit)
            }
        }
        .task(id: status.id) {
            richText = await RichTextCache.shared.richText(for: status)
        }
    }

    @ViewBuilder
    private func content(_ richText: RichText) -> some View {
        let text = Text(attributed(richText))
            .font(bodyFont)
            .foregroundStyle(palette.label)
            .lineSpacing(metrics.lineSpacing)
            .lineLimit(lineLimit)
            .environment(
                \.openURL,
                OpenURLAction { url in
                    guard let link = link(for: url, in: richText) else { return .systemAction }
                    onTap(link)
                    return .handled
                })
        if isSelectable {
            text.textSelection(.enabled)
        } else {
            text
        }
    }

    private var bodyFont: Font {
        let base: Font = metrics.useSerifBody ? .system(.body, design: .serif) : .body
        return base
    }

    private var fallbackText: String {
        // A crude strip, only ever on screen for one frame.
        status.displayed.content
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Links carry a synthetic URL so `Text` can style them; the tap is routed
    /// back to the classified link rather than to Safari.
    private func attributed(_ richText: RichText) -> AttributedString {
        var result = AttributedString()

        for (index, run) in richText.runs.enumerated() {
            var piece = AttributedString(run.text)

            if run.style.contains(.bold) { piece.inlinePresentationIntent = .stronglyEmphasized }
            if run.style.contains(.italic) { piece.inlinePresentationIntent = .emphasized }
            if run.style.contains(.strikethrough) { piece.strikethroughStyle = .single }
            if run.style.contains(.code) {
                piece.font = .system(.callout, design: .monospaced)
                piece.backgroundColor = palette.surfaceRaised
            }
            if run.style.contains(.quote) {
                piece.foregroundColor = palette.secondaryLabel
            }

            switch run.link {
            case .mention:
                piece.foregroundColor = palette.mention
                piece.link = URL(string: "aloha-run://\(index)")
            case .hashtag:
                piece.foregroundColor = palette.hashtag
                piece.link = URL(string: "aloha-run://\(index)")
            case .web:
                piece.foregroundColor = palette.accent
                piece.underlineStyle = .single
                piece.link = URL(string: "aloha-run://\(index)")
            case .none:
                break
            }

            result.append(piece)
        }
        return result
    }

    private func link(for url: URL, in richText: RichText) -> RichText.Link? {
        guard url.scheme == "aloha-run",
            let host = url.host(),
            let index = Int(host),
            richText.runs.indices.contains(index)
        else { return nil }
        return richText.runs[index].link
    }
}

/// Custom emoji rendered inline next to a display name.
public struct EmojiLabel: View {
    private let text: String
    private let emojis: [CustomEmoji]
    private let font: Font

    public init(_ text: String, emojis: [CustomEmoji], font: Font = .body) {
        self.text = text
        self.emojis = emojis
        self.font = font
    }

    public var body: some View {
        // A shortcode with no matching emoji stays literal, which is what the
        // server's own renderer does too.
        Text(text)
            .font(font)
            .lineLimit(1)
    }
}
