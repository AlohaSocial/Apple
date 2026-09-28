// SPDX-License-Identifier: MIT

import AlohaHTML
import AlohaModels
import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Whether the on-device model can be used, and why not when it cannot.
public enum IntelligenceAvailability: Sendable, Hashable {
    case available
    /// Hide the settings section entirely.
    case deviceNotEligible
    /// Show the section, disabled, with the reason.
    case notEnabled
    case modelNotReady
    case unsupportedBuild

    public var isAvailable: Bool { self == .available }

    /// An ineligible device gets no Intelligence UI at all; a device where the
    /// model exists but is not ready gets a disabled section with a reason
    /// (docs/10 §2).
    public var shouldShowSettingsSection: Bool {
        self != .deviceNotEligible && self != .unsupportedBuild
    }

    public var explanation: String? {
        switch self {
        case .available, .deviceNotEligible, .unsupportedBuild: nil
        case .notEnabled:
            String(
                localized: "Turn on Apple Intelligence in Settings to use these.",
                comment: "Intelligence unavailable reason")
        case .modelNotReady:
            String(
                localized: "The on-device model is still downloading.",
                comment: "Intelligence unavailable reason")
        }
    }
}

/// Everything touching the on-device model sits behind this, so `AlohaUI`
/// compiles and tests without `FoundationModels` (docs/01 §3).
public protocol IntelligenceProviding: Sendable {
    var availability: IntelligenceAvailability { get }
    /// Alt text needs Vision rather than the language model, so it is offered
    /// on devices where the rest of this is not.
    var canDescribeImages: Bool { get }
    func rewrite(_ text: String, style: RewriteStyle, maximumCharacters: Int) async throws -> String
    func describeImage(_ imageData: Data) async throws -> String
    func summarise(_ passages: [String]) async throws -> String
}

public enum RewriteStyle: String, Sendable, CaseIterable, Identifiable {
    case proofread, shorten, rephrase, friendlier, formal, concise

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .proofread: String(localized: "Proofread", comment: "Rewrite action")
        case .shorten: String(localized: "Shorten", comment: "Rewrite action")
        case .rephrase: String(localized: "Rephrase", comment: "Rewrite action")
        case .friendlier: String(localized: "Make friendlier", comment: "Rewrite action")
        case .formal: String(localized: "Make more formal", comment: "Rewrite action")
        case .concise: String(localized: "Make more concise", comment: "Rewrite action")
        }
    }

    var instruction: String {
        switch self {
        case .proofread:
            "Fix spelling, grammar and punctuation. Change nothing else — not tone, "
                + "not word choice, not length."
        case .shorten:
            "Reduce the length while preserving the meaning."
        case .rephrase:
            "Say the same thing in different words."
        case .friendlier:
            "Make the tone warmer and friendlier without changing the meaning."
        case .formal:
            "Make the tone more formal without changing the meaning."
        case .concise:
            "Make it more concise without losing anything the writer said."
        }
    }
}

public enum IntelligenceError: Error, Sendable {
    case unavailable
    /// The model declined. Shown plainly, with no retry loop and no prompt
    /// gymnastics (docs/10 §3).
    case refused
    case tooLong
    case failed
}

/// Protects mentions, hashtags and links across a rewrite.
///
/// A rewrite that loses a mention is a rewrite that sends a post to the wrong
/// person, so they are extracted, replaced with placeholders, and restored
/// afterwards (docs/10 §3).
public struct EntityShield: Sendable {
    private var replacements: [String: String] = [:]

    public init() {}

    public mutating func mask(_ text: String) -> String {
        var masked = text
        var index = 0

        let patterns = [
            #"https?://[^\s]+"#,
            #"@[A-Za-z0-9_.-]+(@[A-Za-z0-9.-]+)?"#,
            #"#[\w\p{L}\p{N}_-]+"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            var result = ""
            var last = masked.startIndex
            let full = NSRange(masked.startIndex..., in: masked)

            for match in regex.matches(in: masked, range: full) {
                guard let range = Range(match.range, in: masked) else { continue }
                let token = "⟦\(index)⟧"
                replacements[token] = String(masked[range])
                index += 1
                result += masked[last..<range.lowerBound] + token
                last = range.upperBound
            }
            result += masked[last...]
            masked = result
        }
        return masked
    }

    public func restore(_ text: String) -> String {
        var restored = text
        for (token, original) in replacements {
            restored = restored.replacingOccurrences(of: token, with: original)
        }
        return restored
    }

    /// Every masked entity has to come back, or the rewrite is rejected.
    public func isIntact(_ text: String) -> Bool {
        replacements.keys.allSatisfy { text.contains($0) }
    }

    public var maskedCount: Int { replacements.count }
}

/// The real implementation, or a clearly-unavailable one where the framework
/// is not present in this build.
public struct OnDeviceIntelligence: IntelligenceProviding {
    public init() {}

    public var canDescribeImages: Bool { true }

    public var availability: IntelligenceAvailability {
        #if canImport(FoundationModels)
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return .deviceNotEligible
                case .appleIntelligenceNotEnabled: return .notEnabled
                case .modelNotReady: return .modelNotReady
                @unknown default: return .modelNotReady
                }
            @unknown default:
                return .modelNotReady
            }
        #else
            return .unsupportedBuild
        #endif
    }

    public func rewrite(
        _ text: String, style: RewriteStyle, maximumCharacters: Int
    ) async throws -> String {
        guard availability.isAvailable else { throw IntelligenceError.unavailable }

        var shield = EntityShield()
        let masked = shield.mask(text)

        let instructions = """
            You rewrite social media posts. \(style.instruction)
            Tokens of the form ⟦0⟧ stand for mentions, hashtags and links: reproduce \
            every one of them exactly, unchanged, and do not add new ones.
            Answer with the rewritten text alone and nothing else.
            """

        let answer = try await generate(instructions: instructions, prompt: masked)
        guard shield.isIntact(answer) else { throw IntelligenceError.failed }

        let restored = shield.restore(answer)
        // Rejected rather than shown over-length, so the person is never handed
        // a proposal they cannot post.
        guard restored.count <= maximumCharacters else { throw IntelligenceError.tooLong }
        return restored
    }

    /// Vision reads the picture; the language model turns what it found into a
    /// sentence. The model never sees the image, which is what makes the
    /// "never identify anyone" guardrail enforceable rather than hopeful.
    ///
    /// Works even where the language model is unavailable — the assembled
    /// fallback is blunt but never wrong about what is in the picture.
    public func describeImage(_ imageData: Data) async throws -> String {
        try await ImageDescriber().describe(imageData, using: self)
    }

    public func summarise(_ passages: [String]) async throws -> String {
        guard availability.isAvailable else { throw IntelligenceError.unavailable }

        let instructions = """
            Summarise a conversation for someone deciding whether to read it. \
            Two or three sentences. Neutral. Do not invent anything that is not there.
            """
        let joined = passages.prefix(60).joined(separator: "\n\n")
        return try await generate(instructions: instructions, prompt: joined)
    }

    private func generate(instructions: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                // A guardrail refusal is shown plainly rather than retried.
                throw IntelligenceError.refused
            }
        #else
            throw IntelligenceError.unavailable
        #endif
    }
}

/// Used in previews and tests.
public struct UnavailableIntelligence: IntelligenceProviding {
    public init() {}
    public var availability: IntelligenceAvailability { .deviceNotEligible }
    public var canDescribeImages: Bool { false }
    public func rewrite(
        _ text: String, style: RewriteStyle, maximumCharacters: Int
    ) async throws -> String {
        throw IntelligenceError.unavailable
    }
    public func describeImage(_ imageData: Data) async throws -> String {
        throw IntelligenceError.unavailable
    }
    public func summarise(_ passages: [String]) async throws -> String {
        throw IntelligenceError.unavailable
    }
}

/// Alt text guidance, kept next to the feature that uses it so the rules and
/// the prompt cannot drift apart (docs/10 §4).
public enum AltTextGuidance {
    public static let maximumCharacters = 400

    public static let instructions = """
        Write alternative text for an image, for someone using a screen reader.
        Describe the content and its function objectively, in one or two sentences.
        Do not begin with "image of" or "picture of".
        Do not speculate about who people are, and never describe anyone's name, \
        age, race or presumed gender.
        Do not invent text that is not legibly in the image.
        Stay under \(maximumCharacters) characters.
        """

    /// A last check before the text is put in front of the person.
    public static func looksAcceptable(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let openers = ["image of", "picture of", "photo of", "an image", "a picture"]
        if openers.contains(where: { lowered.hasPrefix($0) }) { return false }
        return !text.isEmpty && text.count <= maximumCharacters
    }
}
