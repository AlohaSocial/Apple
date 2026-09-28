// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// Turns a status's restricted HTML into `RichText`.
///
/// `NSAttributedString`'s HTML importer is WebKit-backed and main-thread-bound,
/// which makes it unusable in a scrolling list — so this is hand-written
/// (docs/01 §3). It is `Sendable` and has no state between calls, so it runs
/// wherever the caller puts it.
public struct StatusHTMLParser: Sendable {

    /// Everything else is stripped to its text content.
    private static let supportedTags: Set<String> = [
        "p", "br", "a", "span", "strong", "b", "em", "i", "del", "s", "code", "pre",
        "blockquote", "ul", "ol", "li", "div",
    ]

    public init() {}

    public func parse(
        _ html: String,
        mentions: [Status.Mention] = [],
        tags: [Status.StatusTag] = [],
        emojis: [CustomEmoji] = []
    ) -> RichText {
        var builder = Builder(mentions: mentions, tags: tags, emojis: emojis)
        var tokenizer = HTMLTokenizer(html)

        while let token = tokenizer.next() {
            switch token {
            case .text(let text):
                builder.append(text: text)
            case .openTag(let name, let attributes, let selfClosing):
                builder.open(tag: name, attributes: attributes)
                if selfClosing { builder.close(tag: name) }
            case .closeTag(let name):
                builder.close(tag: name)
            }
        }
        return builder.finish()
    }

    /// Plain text only, for the cases that never need styling — the search
    /// index, the AI features' input, a notification body.
    public func plainText(_ html: String) -> String {
        parse(html).plainText
    }

    // MARK: - Builder

    private struct Builder {
        let mentions: [Status.Mention]
        let tags: [Status.StatusTag]
        let emojis: [CustomEmoji]

        private var runs: [RichText.Run] = []
        private var blocks: [RichText.Block] = []
        private var plain = ""

        private var styleStack: [RichText.Style] = []
        private var linkStack: [RichText.Link?] = []
        private var blockStart = 0
        private var currentBlockKind: RichText.Block.Kind = .paragraph
        private var listCounters: [Int] = []
        private var orderedStack: [Bool] = []

        init(mentions: [Status.Mention], tags: [Status.StatusTag], emojis: [CustomEmoji]) {
            self.mentions = mentions
            self.tags = tags
            self.emojis = emojis
        }

        private var currentStyle: RichText.Style {
            styleStack.reduce(into: RichText.Style()) { $0.formUnion($1) }
        }

        private var currentLink: RichText.Link? { linkStack.last.flatMap { $0 } }

        mutating func append(text: String) {
            guard !text.isEmpty else { return }
            // Emoji resolution happens on the text run, so a shortcode split
            // across tags is simply not an emoji — which is also true of the
            // server's own renderer.
            for piece in EmojiSplitter.split(text, emojis: emojis) {
                switch piece {
                case .text(let value):
                    guard !value.isEmpty else { continue }
                    runs.append(.init(text: value, style: currentStyle, link: currentLink))
                    plain += value
                case .emoji(let emoji):
                    runs.append(
                        .init(
                            text: ":\(emoji.shortcode):", style: currentStyle,
                            link: currentLink, emoji: emoji))
                    plain += ":\(emoji.shortcode):"
                }
            }
        }

        mutating func open(tag: String, attributes: [String: String]) {
            switch tag {
            case "br":
                runs.append(.init(text: "\n", style: currentStyle))
                plain += "\n"
            case "p", "div":
                closeBlock(.paragraph)
            case "blockquote":
                closeBlock(.paragraph)
                styleStack.append(.quote)
                currentBlockKind = .blockquote
            case "pre":
                closeBlock(.paragraph)
                styleStack.append(.code)
                currentBlockKind = .codeBlock
            case "strong", "b":
                styleStack.append(.bold)
            case "em", "i":
                styleStack.append(.italic)
            case "del", "s":
                styleStack.append(.strikethrough)
            case "code":
                styleStack.append(.code)
            case "ul":
                closeBlock(.paragraph)
                orderedStack.append(false)
                listCounters.append(0)
            case "ol":
                closeBlock(.paragraph)
                orderedStack.append(true)
                listCounters.append(0)
            case "li":
                closeBlock(currentBlockKind)
                if !listCounters.isEmpty { listCounters[listCounters.count - 1] += 1 }
                currentBlockKind = .listItem(
                    ordered: orderedStack.last ?? false, index: listCounters.last ?? 1)
            case "a":
                linkStack.append(resolveLink(attributes))
            case "span":
                // Mastodon wraps the `@` and the domain of a mention in spans
                // with `invisible` / `ellipsis` classes. Both are presentation,
                // and the text inside them is kept — dropping the domain would
                // make two Alices look like one.
                linkStack.append(currentLink)
            default:
                break
            }
        }

        mutating func close(tag: String) {
            switch tag {
            case "p", "div":
                closeBlock(.paragraph)
            case "blockquote", "pre":
                popStyle()
                closeBlock(currentBlockKind)
                currentBlockKind = .paragraph
            case "strong", "b", "em", "i", "del", "s", "code":
                popStyle()
            case "ul", "ol":
                if !orderedStack.isEmpty { orderedStack.removeLast() }
                if !listCounters.isEmpty { listCounters.removeLast() }
                closeBlock(currentBlockKind)
                currentBlockKind = .paragraph
            case "li":
                closeBlock(currentBlockKind)
                currentBlockKind = .paragraph
            case "a", "span":
                if !linkStack.isEmpty { linkStack.removeLast() }
            default:
                break
            }
        }

        private mutating func popStyle() {
            if !styleStack.isEmpty { styleStack.removeLast() }
        }

        private mutating func closeBlock(_ kind: RichText.Block.Kind) {
            guard runs.count > blockStart else {
                currentBlockKind = kind
                return
            }
            blocks.append(.init(kind: currentBlockKind, range: blockStart..<runs.count))
            blockStart = runs.count
            currentBlockKind = kind
            if !plain.hasSuffix("\n") { plain += "\n" }
        }

        /// Link classification is from the `class` attribute plus the status's
        /// own `mentions` and `tags`, which is what makes a tap route in-app.
        private func resolveLink(_ attributes: [String: String]) -> RichText.Link? {
            let href = attributes["href"] ?? ""
            let classes = Set((attributes["class"] ?? "").split(separator: " ").map(String.init))
            let url = URL(string: href)

            if classes.contains("mention") || classes.contains("u-url") {
                // Match on the href against the mention's own URL first; fall
                // back to the handle spelled in the path.
                if let mention = mentions.first(where: { $0.url?.absoluteString == href }) {
                    return .mention(accountID: mention.id, acct: mention.acct, url: url)
                }
                if let handle = Self.handle(fromMentionHref: href),
                    let mention = mentions.first(where: {
                        $0.acct.caseInsensitiveCompare(handle) == .orderedSame
                            || $0.username.caseInsensitiveCompare(handle) == .orderedSame
                    })
                {
                    return .mention(accountID: mention.id, acct: mention.acct, url: url)
                }
                if let handle = Self.handle(fromMentionHref: href) {
                    return .mention(accountID: nil, acct: handle, url: url)
                }
            }

            if classes.contains("hashtag") {
                if let name = Self.tagName(fromHref: href) {
                    let canonical =
                        tags.first {
                            $0.name.caseInsensitiveCompare(name) == .orderedSame
                        }?.name ?? name
                    return .hashtag(name: canonical, url: url)
                }
            }

            guard let url else { return nil }
            return .web(url)
        }

        private static func handle(fromMentionHref href: String) -> String? {
            guard let url = URL(string: href) else { return nil }
            let components = url.pathComponents.filter { $0 != "/" }
            guard let last = components.last(where: { $0.hasPrefix("@") || !$0.isEmpty })
            else { return nil }
            let handle = last.hasPrefix("@") ? String(last.dropFirst()) : last
            guard !handle.isEmpty, let host = url.host() else {
                return handle.isEmpty ? nil : handle
            }
            return handle.contains("@") ? handle : "\(handle)@\(host)"
        }

        private static func tagName(fromHref href: String) -> String? {
            guard let url = URL(string: href) else { return nil }
            guard let last = url.pathComponents.last, !last.isEmpty, last != "/" else { return nil }
            return last.removingPercentEncoding ?? last
        }

        mutating func finish() -> RichText {
            if runs.count > blockStart {
                blocks.append(.init(kind: currentBlockKind, range: blockStart..<runs.count))
            }
            let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
            return RichText(runs: runs, plainText: trimmed, blocks: blocks)
        }
    }
}

/// Splits text around `:shortcode:` occurrences that name a known emoji.
enum EmojiSplitter {
    enum Piece: Sendable, Hashable {
        case text(String)
        case emoji(CustomEmoji)
    }

    static func split(_ text: String, emojis: [CustomEmoji]) -> [Piece] {
        guard !emojis.isEmpty, text.contains(":") else { return [.text(text)] }

        let lookup = Dictionary(
            emojis.map { ($0.shortcode, $0) }, uniquingKeysWith: { first, _ in first })
        var pieces: [Piece] = []
        var buffer = ""
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == ":" else {
                buffer.append(text[index])
                index = text.index(after: index)
                continue
            }

            let after = text.index(after: index)
            // A shortcode is short; scanning further would make a line of prose
            // with two colons cost a linear search each time.
            let limit = text.index(after, offsetBy: 64, limitedBy: text.endIndex) ?? text.endIndex
            guard after < text.endIndex, let closing = text[after..<limit].firstIndex(of: ":")
            else {
                buffer.append(":")
                index = after
                continue
            }

            let shortcode = String(text[after..<closing])
            if let emoji = lookup[shortcode] {
                if !buffer.isEmpty {
                    pieces.append(.text(buffer))
                    buffer = ""
                }
                pieces.append(.emoji(emoji))
                index = text.index(after: closing)
            } else {
                buffer.append(":")
                index = after
            }
        }

        if !buffer.isEmpty { pieces.append(.text(buffer)) }
        return pieces.isEmpty ? [.text("")] : pieces
    }
}
