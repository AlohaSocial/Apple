// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaIntelligence

@Suite("Entity shield")
struct EntityShieldTests {

    /// A rewrite that loses a mention is a rewrite that sends a post to the
    /// wrong person (docs/10 §3).
    @Test("Mentions, hashtags and links survive a round trip")
    func roundTrip() {
        var shield = EntityShield()
        let original = "Hey @alice@example.social, see #SwiftUI and https://example.test/a?b=1"
        let masked = shield.mask(original)

        #expect(masked.contains("@alice") == false)
        #expect(masked.contains("#SwiftUI") == false)
        #expect(masked.contains("https://") == false)
        #expect(shield.maskedCount == 3)
        #expect(shield.restore(masked) == original)
    }

    @Test("A rewrite that drops a token is detected")
    func detectsLostEntities() {
        var shield = EntityShield()
        let masked = shield.mask("Talk to @bob about #plans")
        #expect(shield.isIntact(masked))

        // What a model returns when it "helpfully" removes the placeholders.
        let mangled = masked.replacingOccurrences(of: "⟦0⟧", with: "someone")
        #expect(shield.isIntact(mangled) == false)
    }

    @Test("Text with nothing to protect passes through unchanged")
    func nothingToMask() {
        var shield = EntityShield()
        let plain = "Just some ordinary words."
        #expect(shield.mask(plain) == plain)
        #expect(shield.maskedCount == 0)
    }
}

@Suite("Alt text guidance")
struct AltTextGuidanceTests {

    @Test("Openings that waste a screen reader's time are rejected")
    func rejectsRedundantOpenings() {
        #expect(AltTextGuidance.looksAcceptable("Image of a dog on a beach") == false)
        #expect(AltTextGuidance.looksAcceptable("A picture of a cat") == false)
        #expect(AltTextGuidance.looksAcceptable("A dog running on a beach"))
    }

    @Test("Empty and over-long descriptions are rejected")
    func lengthBounds() {
        #expect(AltTextGuidance.looksAcceptable("") == false)
        #expect(
            AltTextGuidance.looksAcceptable(
                String(repeating: "a", count: AltTextGuidance.maximumCharacters + 1)) == false)
    }
}

@Suite("Image description assembly")
struct ImageDescriptionTests {

    private func observations(
        subjects: [String] = [], text: [String] = [], people: Int = 0
    ) -> ImageDescriber.Observations {
        ImageDescriber.Observations(
            subjects: subjects, recognisedText: text, peopleCount: people,
            isLikelyDocument: false)
    }

    @Test("Subjects become a sentence")
    func subjectsOnly() {
        let result = ImageDescriber.assemble(observations(subjects: ["beach", "sunset"]))
        #expect(result.lowercased().contains("beach"))
        #expect(result.hasSuffix("."))
    }

    /// The guardrail: a count, and nothing else about anybody.
    @Test("People are counted, never described")
    func peopleAreOnlyCounted() {
        let one = ImageDescriber.assemble(observations(subjects: ["park"], people: 1))
        let several = ImageDescriber.assemble(observations(subjects: ["park"], people: 4))

        #expect(one.contains("One person"))
        #expect(several.contains("4 people"))
    }

    @Test("Text found in the image is quoted rather than paraphrased")
    func textIsQuoted() {
        let result = ImageDescriber.assemble(
            observations(subjects: ["sign"], text: ["OPEN", "24 HOURS"]))
        #expect(result.contains("OPEN"))
    }

    @Test("Nothing detected still produces something honest")
    func emptyFallback() {
        let result = ImageDescriber.assemble(observations())
        #expect(result.isEmpty == false)
        #expect(result.hasSuffix("."))
    }

    @Test("The assembly never exceeds the length ceiling")
    func lengthCeiling() {
        let many = (0..<80).map { "subject\($0)" }
        let result = ImageDescriber.assemble(
            observations(subjects: many, text: many, people: 3))
        #expect(result.count <= AltTextGuidance.maximumCharacters)
    }
}
