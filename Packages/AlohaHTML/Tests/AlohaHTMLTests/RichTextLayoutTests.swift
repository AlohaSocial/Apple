// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaHTML

private let parser = StatusHTMLParser()
private let wave = CustomEmoji(shortcode: "wave", url: URL(string: "https://cloud.test/e/wave.png"))

@Suite("Rich text layout")
struct RichTextLayoutTests {

    /// The text a sequence of pieces draws, with emoji as `[shortcode]`.
    private func render(_ pieces: [RichTextLayout.Piece], _ richText: RichText) -> String {
        pieces.map { piece in
            switch piece {
            case .runs(let range): richText.runs[range].map(\.text).joined()
            case .emoji(let emoji, _): "[\(emoji.shortcode)]"
            case .literal(let text): text
            }
        }.joined()
    }

    @Test("Paragraphs stay apart, a blank line between them when flattened")
    func paragraphs() {
        let text = parser.parse("<p>One</p><p>Two</p>")
        let layout = RichTextLayout(text)
        #expect(layout.blocks.count == 2)
        #expect(!layout.hasStructure)
        #expect(render(layout.flattened, text) == "One\n\nTwo")
    }

    @Test("List items carry their bullet or number, one line apart")
    func lists() {
        let bullets = parser.parse("<p>Before</p><ul><li>a</li><li>b</li></ul>")
        let layout = RichTextLayout(bullets)
        #expect(layout.hasStructure)
        #expect(layout.blocks.map(\.marker) == [nil, "•", "•"])
        #expect(render(layout.flattened, bullets) == "Before\n\n• a\n• b")

        let numbers = RichTextLayout(parser.parse("<ol><li>a</li><li>b</li></ol>"))
        #expect(numbers.blocks.map(\.marker) == ["1.", "2."])
        #expect(numbers.blocks.allSatisfy { $0.kind == .listItem })
    }

    @Test("A quote and a code block are kinds of their own")
    func quoteAndCode() {
        let layout = RichTextLayout(
            parser.parse("<blockquote><p>said</p></blockquote><pre><code>let x</code></pre>"))
        #expect(layout.blocks.map(\.kind).contains(.quote))
        #expect(layout.blocks.map(\.kind).contains(.code))
    }

    @Test("Line breaks at a block's edges draw no empty line")
    func trimsEdges() {
        let text = parser.parse("<p><br>Hello<br></p>")
        let layout = RichTextLayout(text)
        #expect(render(layout.flattened, text) == "Hello")
    }

    @Test("A custom emoji interrupts the text as a piece of its own")
    func emojiPieces() {
        let text = parser.parse("<p>Hi :wave: there</p>", emojis: [wave])
        let layout = RichTextLayout(text)
        #expect(layout.hasEmoji)
        #expect(layout.emojis == [wave])
        #expect(render(layout.flattened, text) == "Hi [wave] there")
        let pieces = layout.blocks[0].pieces
        #expect(pieces.count == 3)
        if case .emoji(let emoji, _) = pieces[1] {
            #expect(emoji.shortcode == "wave")
        } else {
            Issue.record("the middle piece should be the emoji")
        }
    }

    @Test("An unknown shortcode stays text")
    func unknownShortcode() {
        let text = parser.parse("<p>Hi :nope:</p>", emojis: [wave])
        let layout = RichTextLayout(text)
        #expect(!layout.hasEmoji)
        #expect(render(layout.flattened, text) == "Hi :nope:")
    }

    @Test("A display name with emoji splits the same way")
    func inlineName() {
        let name = RichText.inline("Alice :wave:", emojis: [wave])
        let layout = RichTextLayout(name)
        #expect(render(layout.flattened, name) == "Alice [wave]")
        #expect(name.plainText == "Alice :wave:")
    }

    @Test("Empty content lays out nothing")
    func empty() {
        #expect(RichTextLayout(.empty).blocks.isEmpty)
        #expect(RichTextLayout(RichText.inline("", emojis: [])).flattened.isEmpty)
    }
}
