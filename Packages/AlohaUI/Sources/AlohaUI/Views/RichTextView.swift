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
///
/// A post laid out in full keeps its shape: paragraphs apart, lists with
/// their bullets and numbers, a quote with its bar, code in a block of its
/// own. A line-limited excerpt is one `Text`, so its truncation lands at the
/// end of what fits rather than at the end of the first paragraph. A
/// translation, once asked for, is drawn here, in place of the original,
/// with a way back to it.
public struct RichTextView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics
    /// Optional: the composer's reply preview runs in the share extension,
    /// which has no translator.
    @Environment(Translator.self) private var translator: Translator?
    @ScaledMetric(relativeTo: .body) private var emojiSize: CGFloat = 20

    private let status: Status
    private let lineLimit: Int?
    private let isSelectable: Bool
    private let onTap: (RichText.Link) -> Void

    @State private var rendered: Rendered?
    @State private var translated: Rendered?

    public init(
        status: Status, lineLimit: Int? = nil, isSelectable: Bool = false,
        onTap: @escaping (RichText.Link) -> Void = { _ in }
    ) {
        self.status = status
        self.lineLimit = lineLimit
        self.isSelectable = isSelectable
        self.onTap = onTap
    }

    /// A parse and its layout, computed together so they cannot disagree.
    struct Rendered: Equatable {
        var richText: RichText
        var layout: RichTextLayout

        init(_ richText: RichText) {
            self.richText = richText
            self.layout = RichTextLayout(richText)
        }
    }

    /// What the parse depends on. An edit keeps the post's id, so keying on
    /// the id alone left an edited post showing its old words.
    private struct RenderKey: Hashable {
        var id: String
        var content: String
        var editedAt: Date?
        var emojis: [CustomEmoji]
    }

    private var displayed: Status { status.displayed }

    private var renderKey: RenderKey {
        RenderKey(
            id: displayed.id, content: displayed.content, editedAt: displayed.editedAt,
            emojis: displayed.emojis)
    }

    private var translation: Translator.Result? {
        translator?.translation(for: displayed.id)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            if let translation, let translated {
                content(translated)
                translationFooter(translation)
            } else if let rendered {
                content(rendered)
                if translator?.inFlight.contains(displayed.id) == true { translatingLine }
            } else {
                // The one-frame fallback. Never a spinner, never empty space.
                Text(fallbackText)
                    .font(bodyFont)
                    .foregroundStyle(palette.label)
                    .lineLimit(lineLimit)
            }
        }
        .task(id: renderKey) {
            let parsed = Rendered(await RichTextCache.shared.richText(for: status))
            EmojiImages.shared.load(parsed.layout.emojis)
            rendered = parsed
        }
        .task(id: translation) {
            guard let translation else {
                translated = nil
                return
            }
            translated = Rendered(Self.parse(translation, of: displayed))
        }
    }

    private static func parse(_ translation: Translator.Result, of status: Status) -> RichText {
        let parser = StatusHTMLParser()
        if translation.isHTML {
            return parser.parse(
                translation.content, mentions: status.mentions, tags: status.tags,
                emojis: status.emojis)
        }
        // The device translated plain text; its line breaks are the
        // paragraphs it was given.
        let paragraphs = translation.content
            .components(separatedBy: "\n")
            .map { "<p>\(Self.escaped($0))</p>" }
            .joined()
        return parser.parse(paragraphs, emojis: status.emojis)
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Layout

    @ViewBuilder
    private func content(_ rendered: Rendered) -> some View {
        let laidOut = Group {
            if lineLimit != nil || !rendered.layout.hasStructure {
                text(rendered.layout.flattened, in: rendered.richText)
                    .lineLimit(lineLimit)
            } else {
                VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                    ForEach(Array(rendered.layout.blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block, in: rendered.richText)
                    }
                }
            }
        }
        .font(bodyFont)
        .foregroundStyle(palette.label)
        .lineSpacing(metrics.lineSpacing)
        .environment(
            \.openURL,
            OpenURLAction { url in
                guard let link = link(for: url, in: rendered.richText) else { return .systemAction }
                onTap(link)
                return .handled
            })

        if isSelectable {
            laidOut.textSelection(.enabled)
        } else {
            laidOut
        }
    }

    @ViewBuilder
    private func blockView(_ block: RichTextLayout.Block, in richText: RichText) -> some View {
        switch block.kind {
        case .paragraph:
            text(block.pieces, in: richText)
        case .listItem:
            HStack(alignment: .firstTextBaseline, spacing: AlohaMetrics.space2) {
                Text(verbatim: block.marker ?? "•")
                    .monospacedDigit()
                    .foregroundStyle(palette.secondaryLabel)
                    .accessibilityHidden(block.marker == "•")
                text(block.pieces, in: richText)
            }
            .padding(.leading, AlohaMetrics.space2)
        case .quote:
            text(block.pieces, in: richText)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.leading, AlohaMetrics.space3)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(palette.separator)
                        .frame(width: 3)
                }
        case .code:
            text(block.pieces, in: richText)
                .font(.system(.callout, design: .monospaced))
                .padding(AlohaMetrics.space2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    palette.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
                )
        }
    }

    /// Pieces as one `Text`. Plain text stays a single attributed string;
    /// only a body with a custom emoji is stitched from parts, because a
    /// picture cannot live inside an `AttributedString` a `Text` draws.
    private func text(_ pieces: [RichTextLayout.Piece], in richText: RichText) -> Text {
        let hasEmoji = pieces.contains {
            if case .emoji = $0 { return true }
            return false
        }
        guard hasEmoji else { return Text(attributed(pieces, in: richText)) }

        var parts: [Text] = []
        var pending: [RichTextLayout.Piece] = []
        func flush() {
            if !pending.isEmpty { parts.append(Text(attributed(pending, in: richText))) }
            pending.removeAll()
        }
        for piece in pieces {
            guard case .emoji(let emoji, let run) = piece else {
                pending.append(piece)
                continue
            }
            flush()
            if let image = EmojiImages.shared.image(for: emoji) {
                parts.append(
                    Text.emoji(image, pointSize: emojiSize)
                        .accessibilityLabel(Text(verbatim: emoji.shortcode)))
            } else if EmojiImages.shared.hasFailed(emoji) {
                parts.append(Text(attributed([.runs(run..<run + 1)], in: richText)))
            } else {
                // Room for the picture while it loads, so the line does not
                // reflow when it arrives.
                parts.append(Text(verbatim: "\u{2003}"))
            }
        }
        flush()
        return Text.concatenating(parts)
    }

    private var bodyFont: Font {
        let base: Font = metrics.useSerifBody ? .system(.body, design: .serif) : .body
        return base
    }

    private var fallbackText: String {
        // A crude strip, only ever on screen for one frame.
        displayed.content
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Links carry a synthetic URL so `Text` can style them; the tap is routed
    /// back to the classified link rather than to Safari.
    private func attributed(
        _ pieces: [RichTextLayout.Piece], in richText: RichText
    ) -> AttributedString {
        var result = AttributedString()
        for piece in pieces {
            switch piece {
            case .literal(let text):
                result.append(AttributedString(text))
            case .runs(let range):
                for index in range { result.append(attributed(richText.runs[index], index: index)) }
            case .emoji(_, let run):
                result.append(attributed(richText.runs[run], index: run))
            }
        }
        return result
    }

    private func attributed(_ run: RichText.Run, index: Int) -> AttributedString {
        var piece = AttributedString(run.text)

        var intent: InlinePresentationIntent = []
        if run.style.contains(.bold) { intent.insert(.stronglyEmphasized) }
        if run.style.contains(.italic) { intent.insert(.emphasized) }
        if !intent.isEmpty { piece.inlinePresentationIntent = intent }
        if run.style.contains(.strikethrough) { piece.strikethroughStyle = .single }
        if run.style.contains(.code) {
            piece.font = .system(.callout, design: .monospaced)
            piece.backgroundColor = palette.surfaceRaised
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
        return piece
    }

    private func link(for url: URL, in richText: RichText) -> RichText.Link? {
        guard url.scheme == "aloha-run",
            let host = url.host(),
            let index = Int(host),
            richText.runs.indices.contains(index)
        else { return nil }
        return richText.runs[index].link
    }

    // MARK: - Translation

    private var translatingLine: some View {
        HStack(spacing: AlohaMetrics.space2) {
            ProgressView()
                .controlSize(.mini)
            Text("Translating…", comment: "Shown under a post while it is being translated")
        }
        .font(.footnote)
        .foregroundStyle(palette.secondaryLabel)
    }

    private func translationFooter(_ translation: Translator.Result) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: "translate")
                .accessibilityHidden(true)
            Text(verbatim: translation.attribution)
            if let source = translation.detectedSourceLanguage,
                let name = Locale.current.localizedString(forLanguageCode: source)
            {
                Text("from \(name)", comment: "Translation source language, e.g. 'from French'")
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeOut(duration: 0.18)) { translator?.clear(displayed.id) }
            } label: {
                Text("Show original", comment: "Undo a translation shown in place")
            }
            .buttonStyle(.borderless)
        }
        .font(.footnote)
        .foregroundStyle(palette.secondaryLabel)
    }
}

/// A display name or a content warning with its custom emoji drawn.
///
/// Both are plain text on the wire that can still carry `:shortcode:`s the
/// account or the post names; without this they read as raw shortcodes.
public struct EmojiLabel: View {
    @ScaledMetric private var emojiSize: CGFloat

    private let text: String
    private let emojis: [CustomEmoji]
    private let lineLimit: Int?

    public init(
        _ text: String, emojis: [CustomEmoji], relativeTo textStyle: Font.TextStyle = .body,
        lineLimit: Int? = 1
    ) {
        self.text = text
        self.emojis = emojis
        self.lineLimit = lineLimit
        _emojiSize = ScaledMetric(
            wrappedValue: Self.baseSize(for: textStyle), relativeTo: textStyle)
    }

    private static func baseSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }

    public var body: some View {
        label
            .lineLimit(lineLimit)
            .task(id: emojis) { EmojiImages.shared.load(usedEmojis) }
            // The words, not the pictures: a shortcode is what a screen
            // reader would otherwise spell out letter by letter.
            .accessibilityLabel(Text(verbatim: text))
    }

    private var usedEmojis: [CustomEmoji] {
        emojis.filter { text.contains(":\($0.shortcode):") }
    }

    private var label: Text {
        // A shortcode with no matching emoji stays literal, which is what the
        // server's own renderer does too.
        guard !emojis.isEmpty, text.contains(":") else { return Text(verbatim: text) }
        let inline = RichText.inline(text, emojis: emojis)
        var parts: [Text] = []
        for run in inline.runs {
            if let emoji = run.emoji, let image = EmojiImages.shared.image(for: emoji) {
                parts.append(Text.emoji(image, pointSize: emojiSize * 1.1))
            } else if let emoji = run.emoji, !EmojiImages.shared.hasFailed(emoji) {
                parts.append(Text(verbatim: "\u{2003}"))
            } else {
                parts.append(Text(verbatim: run.text))
            }
        }
        return Text.concatenating(parts)
    }
}
