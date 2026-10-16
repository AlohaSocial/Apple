// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaHTML

private let parser = StatusHTMLParser()

@Suite("Rich text as an AttributedString")
struct AttributedStringTests {

    @Test("Paragraphs become lines and the text survives")
    func paragraphs() {
        let text = parser.parse("<p>One</p><p>Two <strong>three</strong></p>").attributedString
        #expect(String(text.characters) == "One\nTwo three")
    }

    @Test("Bold and italic become presentation intents")
    func emphasis() throws {
        let text = parser.parse("<p><strong>bold</strong> <em>soft</em></p>").attributedString
        let bold = try #require(text.range(of: "bold"))
        let soft = try #require(text.range(of: "soft"))
        #expect(text[bold].inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
        #expect(text[soft].inlinePresentationIntent?.contains(.emphasized) == true)
    }

    @Test("A web link keeps its destination")
    func links() throws {
        let text = parser.parse(#"<p>See <a href="https://example.test/a">this</a></p>"#)
            .attributedString
        let range = try #require(text.range(of: "this"))
        #expect(text[range].link == URL(string: "https://example.test/a"))
    }

    @Test("List items keep their bullets and numbers")
    func lists() {
        let bullets = parser.parse("<ul><li>a</li><li>b</li></ul>").attributedString
        #expect(String(bullets.characters) == "• a\n• b")
        let numbers = parser.parse("<ol><li>a</li><li>b</li></ol>").attributedString
        #expect(String(numbers.characters) == "1. a\n2. b")
    }

    @Test("Empty HTML is an empty string")
    func empty() {
        #expect(parser.parse("").attributedString.characters.isEmpty)
    }
}
