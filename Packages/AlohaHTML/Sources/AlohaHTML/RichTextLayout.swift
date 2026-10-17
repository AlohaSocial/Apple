// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// How a parsed body is laid out: which blocks stand apart, what marks a
/// list item, and where a custom emoji interrupts the text.
///
/// Foundation only, so the decisions are testable here and the renderer is
/// left with drawing. The renderer works in two modes: block layout, where a
/// list, a quote or a code block keeps its shape, and a flat sequence for a
/// line-limited excerpt, where one `Text` has to carry the whole body so its
/// truncation lands in the right place.
public struct RichTextLayout: Sendable, Hashable {
    public var blocks: [Block]

    public struct Block: Sendable, Hashable {
        public var kind: Kind
        /// `•` or `3.` for a list item; nil otherwise.
        public var marker: String?
        public var pieces: [Piece]
    }

    public enum Kind: Sendable, Hashable {
        case paragraph
        case listItem
        case quote
        case code
    }

    public enum Piece: Sendable, Hashable {
        /// Consecutive runs drawn as styled text.
        case runs(Range<Int>)
        /// One run that is a custom emoji, drawn as its picture.
        case emoji(CustomEmoji, run: Int)
        /// Text the layout adds itself: a paragraph break, a list marker.
        case literal(String)
    }

    public init(_ richText: RichText) {
        let source =
            richText.blocks.isEmpty
            ? [RichText.Block(kind: .paragraph, range: richText.runs.indices)]
            : richText.blocks

        blocks = source.compactMap { block in
            let range = Self.trimmed(block.range, in: richText.runs)
            guard !range.isEmpty else { return nil }
            let kind: Kind
            var marker: String?
            switch block.kind {
            case .paragraph: kind = .paragraph
            case .blockquote: kind = .quote
            case .codeBlock: kind = .code
            case .listItem(let ordered, let index):
                kind = .listItem
                marker = ordered ? "\(index)." : "•"
            }
            return Block(
                kind: kind, marker: marker, pieces: Self.pieces(range, in: richText.runs))
        }
    }

    /// Whether anything needs more than one paragraph's worth of layout.
    public var hasStructure: Bool {
        blocks.contains { $0.kind != .paragraph }
    }

    /// Whether any run is drawn as a picture.
    public var hasEmoji: Bool {
        blocks.contains { block in
            block.pieces.contains {
                if case .emoji = $0 { return true }
                return false
            }
        }
    }

    /// The whole body as one sequence, for a single line-limited `Text`.
    ///
    /// Paragraphs are a blank line apart and list items one line apart, so
    /// an excerpt still reads as the post it was cut from; a list item keeps
    /// its marker.
    public var flattened: [Piece] {
        var result: [Piece] = []
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                let previous = blocks[index - 1].kind
                let tight = previous == .listItem && block.kind == .listItem
                result.append(.literal(tight ? "\n" : "\n\n"))
            }
            if let marker = block.marker { result.append(.literal("\(marker) ")) }
            result.append(contentsOf: block.pieces)
        }
        return result
    }

    /// Emoji the body draws, deduplicated, for loading their pictures.
    public var emojis: [CustomEmoji] {
        var seen = Set<String>()
        var result: [CustomEmoji] = []
        for block in blocks {
            for case .emoji(let emoji, _) in block.pieces
            where seen.insert(emoji.shortcode).inserted {
                result.append(emoji)
            }
        }
        return result
    }

    /// A block without the line breaks a `<br>` left at either edge, which
    /// would otherwise draw as an empty first or last line.
    static func trimmed(_ range: Range<Int>, in runs: [RichText.Run]) -> Range<Int> {
        let clamped = range.clamped(to: runs.indices)
        var lower = clamped.lowerBound
        var upper = clamped.upperBound
        while lower < upper, isBlank(runs[lower]) { lower += 1 }
        while upper > lower, isBlank(runs[upper - 1]) { upper -= 1 }
        return lower..<upper
    }

    private static func isBlank(_ run: RichText.Run) -> Bool {
        run.emoji == nil && run.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Text runs grouped, emoji runs on their own.
    static func pieces(_ range: Range<Int>, in runs: [RichText.Run]) -> [Piece] {
        var pieces: [Piece] = []
        var start: Int?
        for index in range {
            if let emoji = runs[index].emoji {
                if let open = start { pieces.append(.runs(open..<index)) }
                start = nil
                pieces.append(.emoji(emoji, run: index))
            } else if start == nil {
                start = index
            }
        }
        if let open = start { pieces.append(.runs(open..<range.upperBound)) }
        return pieces
    }
}

extension RichText {
    /// Emoji-only text (`:blobcat:`) for a display name or a content warning,
    /// which are plain text on the wire but still carry custom emoji.
    public static func inline(_ text: String, emojis: [CustomEmoji]) -> RichText {
        var runs: [Run] = []
        for piece in EmojiSplitter.split(text, emojis: emojis) {
            switch piece {
            case .text(let value) where !value.isEmpty:
                runs.append(Run(text: value))
            case .emoji(let emoji):
                runs.append(Run(text: ":\(emoji.shortcode):", emoji: emoji))
            case .text:
                break
            }
        }
        return RichText(
            runs: runs, plainText: text,
            blocks: [Block(kind: .paragraph, range: runs.indices)])
    }
}
