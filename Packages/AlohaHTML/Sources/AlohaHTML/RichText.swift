// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

/// A parsed status body.
///
/// Carries both the styled runs and a plain-text projection — the latter is
/// what search, the AI features and VoiceOver read, and building it twice would
/// be two chances to disagree.
public struct RichText: Sendable, Hashable {
    public var runs: [Run]
    public var plainText: String
    /// Blocks let a renderer lay out paragraphs and lists without re-walking.
    public var blocks: [Block]

    public init(runs: [Run], plainText: String, blocks: [Block]) {
        self.runs = runs
        self.plainText = plainText
        self.blocks = blocks
    }

    public static let empty = RichText(runs: [], plainText: "", blocks: [])

    public var isEmpty: Bool { plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public struct Run: Sendable, Hashable {
        public var text: String
        public var style: Style
        public var link: Link?
        /// Set where the run is a custom emoji standing in for `:shortcode:`.
        public var emoji: CustomEmoji?

        public init(text: String, style: Style = [], link: Link? = nil, emoji: CustomEmoji? = nil) {
            self.text = text
            self.style = style
            self.link = link
            self.emoji = emoji
        }
    }

    public struct Style: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let bold = Style(rawValue: 1 << 0)
        public static let italic = Style(rawValue: 1 << 1)
        public static let strikethrough = Style(rawValue: 1 << 2)
        public static let code = Style(rawValue: 1 << 3)
        public static let quote = Style(rawValue: 1 << 4)
    }

    /// A link's destination, already resolved against the status's own
    /// `mentions` and `tags` so a tap routes in-app rather than to Safari.
    public enum Link: Sendable, Hashable {
        case mention(accountID: String?, acct: String, url: URL?)
        case hashtag(name: String, url: URL?)
        case web(URL)
    }

    public struct Block: Sendable, Hashable {
        public var kind: Kind
        /// Indices into `runs`.
        public var range: Range<Int>

        public enum Kind: Sendable, Hashable {
            case paragraph
            case listItem(ordered: Bool, index: Int)
            case blockquote
            case codeBlock
        }

        public init(kind: Kind, range: Range<Int>) {
            self.kind = kind
            self.range = range
        }
    }
}

extension RichText {
    public var mentions: [String] {
        runs.compactMap { run in
            if case .mention(_, let acct, _) = run.link { return acct }
            return nil
        }
    }

    public var hashtags: [String] {
        runs.compactMap { run in
            if case .hashtag(let name, _) = run.link { return name }
            return nil
        }
    }

    public var webLinks: [URL] {
        runs.compactMap { run in
            if case .web(let url) = run.link { return url }
            return nil
        }
    }
}
