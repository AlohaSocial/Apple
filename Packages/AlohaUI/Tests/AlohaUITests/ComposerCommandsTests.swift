// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaUI

/// A source of numbers a test can know the answer to. `@unchecked Sendable`
/// because the closure it hands out is called synchronously from one task.
private final class Dice: @unchecked Sendable {
    private var values: [Double]
    private var index = 0

    init(_ values: [Double]) { self.values = values }

    var source: ComposerCommands.RandomSource {
        { [self] in
            defer { index += 1 }
            return values.indices.contains(index) ? values[index] : 0
        }
    }
}

@Suite("Composer games")
struct ComposerCommandsTests {

    @Test("A die is replaced by its face")
    func diceRolls() {
        let (text, results) = ComposerCommands.resolve(
            "rolling /dice now", random: Dice([0.5]).source)
        #expect(text == "rolling 🎲 4 now")
        #expect(results.count == 1)
        #expect(results.first?.kind == .dice)
        #expect(results.first?.sides == 6)
    }

    @Test("A die with sides says which die it was")
    func diceWithSides() {
        let (text, _) = ComposerCommands.resolve("/dice d20", random: Dice([0.0]).source)
        #expect(text == "🎲 1 (d20)")
    }

    @Test("Sides are clamped rather than obeyed")
    func sidesClamped() {
        // 1 would be a die with one face, so it becomes two; 9999 is past the
        // ceiling. Neither is six, so both say which die they were.
        let (low, results) = ComposerCommands.resolve("/dice 1", random: Dice([0.99]).source)
        #expect(low == "🎲 2 (d2)")
        #expect(results.first?.sides == 2)
        let (high, capped) = ComposerCommands.resolve("/dice 9999", random: Dice([0.0]).source)
        #expect(high == "🎲 1 (d1000)")
        #expect(capped.first?.sides == ComposerCommands.maximumSides)
    }

    @Test("A coin lands on one of two faces")
    func flip() {
        let (heads, _) = ComposerCommands.resolve("/flip", random: Dice([0.1]).source)
        let (tails, _) = ComposerCommands.resolve("/flip", random: Dice([0.9]).source)
        #expect(heads != tails)
        #expect(heads.hasPrefix("🪙 "))
    }

    @Test("Pick chooses from a comma list")
    func pickCommas() {
        let (text, results) = ComposerCommands.resolve(
            "/pick pizza, pasta, salad", random: Dice([0.5]).source)
        #expect(text.hasPrefix("🎯 pasta"))
        #expect(results.first?.options == ["pizza", "pasta", "salad"])
    }

    @Test("Pick falls back to splitting on “or”")
    func pickOr() {
        let (_, results) = ComposerCommands.resolve(
            "/pick tea or coffee", random: Dice([0.0]).source)
        #expect(results.first?.options == ["tea", "coffee"])
    }

    @Test("Pick with nothing to choose between is left as typed")
    func pickNeedsTwo() {
        let (text, results) = ComposerCommands.resolve("/pick pizza", random: Dice([0]).source)
        #expect(text == "/pick pizza")
        #expect(results.isEmpty)
    }

    @Test("A command inside a link is not a command")
    func linksAreLeftAlone() {
        let url = "https://example.org/dice/roll"
        let (text, results) = ComposerCommands.resolve(url, random: Dice([0.5]).source)
        #expect(text == url)
        #expect(results.isEmpty)
    }

    @Test("Pick runs to the end of its line and no further")
    func pickStopsAtNewline() {
        let (text, results) = ComposerCommands.resolve(
            "/pick tea, coffee\nand then /flip", random: Dice([0.0, 0.1]).source)
        #expect(results.count == 2)
        #expect(results.first?.kind == .pick)
        #expect(results.last?.kind == .flip)
        #expect(text.contains("\n"))
    }

    @Test("Two games on one line are both played")
    func twoOnOneLine() {
        let (_, results) = ComposerCommands.resolve(
            "/flip then /dice", random: Dice([0.1, 0.5]).source)
        #expect(results.map(\.kind) == [.flip, .dice])
    }

    @Test("The hint lists each kind once, in order")
    func hint() {
        #expect(ComposerCommands.commands(in: "/dice /flip /dice") == [.dice, .flip])
        #expect(ComposerCommands.commands(in: "nothing here").isEmpty)
        // A pick with one option is not a game, so it is not hinted either.
        #expect(ComposerCommands.commands(in: "/pick one").isEmpty)
    }

    @Test("A source that hands back 1.0 does not run off the end")
    func randomAtTheCeiling() {
        let (text, results) = ComposerCommands.resolve(
            "/pick a, b", random: Dice([1.0]).source)
        #expect(results.first?.result == "b")
        #expect(text.hasPrefix("🎯 b"))
    }

    @Test("Text with no command comes back untouched")
    func noCommands() {
        let original = "just an ordinary post"
        let (text, results) = ComposerCommands.resolve(original)
        #expect(text == original)
        #expect(results.isEmpty)
    }
}

@Suite("Short posts as cards")
struct TextCardTests {

    @Test("Short, alone and not a poll")
    func fits() {
        #expect(TextCard.fits("hello", attachments: 0, hasPoll: false))
        #expect(!TextCard.fits("", attachments: 0, hasPoll: false))
        #expect(!TextCard.fits("   ", attachments: 0, hasPoll: false))
        #expect(!TextCard.fits("hello", attachments: 1, hasPoll: false))
        #expect(!TextCard.fits("hello", attachments: 0, hasPoll: true))
    }

    @Test("Past the character limit it is an ordinary post")
    func tooLong() {
        let words = String(repeating: "a", count: TextCard.characterLimit + 1)
        #expect(!TextCard.fits(words, attachments: 0, hasPoll: false))
        #expect(
            TextCard.fits(
                String(repeating: "a", count: TextCard.characterLimit),
                attachments: 0, hasPoll: false))
    }

    @Test("Six backgrounds, the first the writer's own")
    func backgrounds() {
        let backgrounds = TextCard.backgrounds(accountHue: 120)
        #expect(backgrounds.count == 6)
        #expect(backgrounds.first?.id == "account")
        #expect(Set(backgrounds.map(\.id)).count == 6)
    }
}
