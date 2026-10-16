// SPDX-License-Identifier: MIT

import Foundation

extension RichText {
    /// The body as one `AttributedString`, for a surface that draws a status
    /// with a plain `Text` rather than the app's block renderer — the watch,
    /// which has room for neither custom emoji images nor quote bars.
    ///
    /// Emphasis, strikethrough, code and links survive; blocks become lines,
    /// with list items keeping their bullet or number so a list still reads as
    /// one. Foundation only, so it compiles wherever this package does.
    public var attributedString: AttributedString {
        var result = AttributedString()
        let paragraphs = blocks.isEmpty ? [Block(kind: .paragraph, range: runs.indices)] : blocks

        for (index, block) in paragraphs.enumerated() {
            if index > 0 { result.append(AttributedString("\n")) }
            switch block.kind {
            case .listItem(let ordered, let number):
                result.append(AttributedString(ordered ? "\(number). " : "• "))
            case .paragraph, .blockquote, .codeBlock:
                break
            }
            let runs = runs[block.range.clamped(to: self.runs.indices)]
            for run in runs {
                result.append(Self.attributed(run, in: block.kind))
            }
        }
        return result
    }

    private static func attributed(_ run: Run, in kind: Block.Kind) -> AttributedString {
        var piece = AttributedString(run.text)
        var intent: InlinePresentationIntent = []
        if run.style.contains(.bold) { intent.insert(.stronglyEmphasized) }
        if run.style.contains(.italic) || kind == .blockquote { intent.insert(.emphasized) }
        if run.style.contains(.strikethrough) { intent.insert(.strikethrough) }
        if run.style.contains(.code) || kind == .codeBlock { intent.insert(.code) }
        if !intent.isEmpty { piece.inlinePresentationIntent = intent }

        switch run.link {
        case .web(let url): piece.link = url
        case .mention(_, _, let url), .hashtag(_, let url): piece.link = url
        case nil: break
        }
        return piece
    }
}
