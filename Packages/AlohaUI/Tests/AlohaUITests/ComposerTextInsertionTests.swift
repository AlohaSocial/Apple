// SPDX-License-Identifier: MIT

import Testing
import UniformTypeIdentifiers

@testable import AlohaUI

@Suite("An emoji goes where the cursor is")
struct ComposerTextInsertionTests {
    @Test("With no cursor it goes at the end, after a space")
    func appendsWithoutCursor() {
        let result = ComposerTextInsertion.inserting(":wave:", into: "Hello", replacing: nil)
        #expect(result.text == "Hello :wave: ")
        #expect(result.cursorOffset == result.text.count)
    }

    @Test("In the middle of a sentence it goes between the words")
    func insertsAtCursor() {
        let text = "Good morning"
        let cursor = text.index(text.startIndex, offsetBy: 5)
        let result = ComposerTextInsertion.inserting(
            ":sun:", into: text, replacing: cursor..<cursor)
        #expect(result.text == "Good :sun: morning")
        // After the emoji and its space, before "morning".
        #expect(result.cursorOffset == "Good :sun: ".count)
    }

    @Test("A selection is replaced, the way a typed character replaces it")
    func replacesSelection() {
        let text = "I love cats"
        let start = text.index(text.startIndex, offsetBy: 2)
        let end = text.index(start, offsetBy: 4)
        let result = ComposerTextInsertion.inserting(
            ":heart:", into: text, replacing: start..<end)
        #expect(result.text == "I :heart: cats")
    }

    @Test("An empty post gets no leading space")
    func emptyText() {
        let result = ComposerTextInsertion.inserting(":wave:", into: "", replacing: nil)
        #expect(result.text == ":wave: ")
    }

    @Test("A movie is asked for before an image, so it is never taken for a still")
    func movieBeforeImage() {
        #expect(DroppedMedia.acceptedTypes == [.movie, .image])
    }
}
