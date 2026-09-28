// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import ImageIO
import Vision

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Alt text, generated entirely on this device.
///
/// `FoundationModels` is a text model — it takes no image — so the picture is
/// read by **Vision** and the observations are handed to the language model to
/// turn into a sentence. Both are on-device, which is what keeps the privacy
/// statement in docs/10 §8 true.
///
/// Vision is also what makes the guardrail enforceable rather than hopeful: the
/// model never sees the image, only a list of things, so it cannot volunteer
/// who somebody is (docs/10 §4).
public struct ImageDescriber: Sendable {

    public init() {}

    /// What Vision found. Deliberately coarse.
    public struct Observations: Sendable, Hashable {
        public var subjects: [String]
        public var recognisedText: [String]
        public var peopleCount: Int
        public var isLikelyDocument: Bool

        public var isEmpty: Bool {
            subjects.isEmpty && recognisedText.isEmpty && peopleCount == 0
        }
    }

    public func observe(_ imageData: Data) async throws -> Observations {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw IntelligenceError.failed }

        async let classifications = classify(image)
        async let text = readText(image)
        async let people = countPeople(image)

        let subjects = try await classifications
        let recognised = try await text

        return Observations(
            subjects: subjects,
            recognisedText: recognised,
            peopleCount: try await people,
            // A page of words with nothing else in it is a screenshot or a
            // document, and reads better described as one.
            isLikelyDocument: subjects.isEmpty && recognised.count > 3)
    }

    private func classify(_ image: CGImage) async throws -> [String] {
        let request = ClassifyImageRequest()
        let results = try await request.perform(on: image)
        return
            results
            .filter { $0.confidence > 0.35 }
            .prefix(6)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }

    private func readText(_ image: CGImage) async throws -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        let results = try await request.perform(on: image)
        let strings: [String] = results.compactMap { $0.topCandidates(1).first?.string }
        return Array(strings.filter { $0.count > 1 }.prefix(8))
    }

    /// A count, never an identity. Vision can do far more here and is
    /// deliberately not asked to.
    private func countPeople(_ image: CGImage) async throws -> Int {
        let request = DetectFaceRectanglesRequest()
        return try await request.perform(on: image).count
    }

    // MARK: - Composition

    /// Turns observations into a sentence, with the model where it is
    /// available and a plain assembly where it is not. Either way the result is
    /// a draft the person reviews.
    public func describe(
        _ imageData: Data, using model: (any IntelligenceProviding)? = nil
    ) async throws -> String {
        let observations = try await observe(imageData)
        guard !observations.isEmpty else { throw IntelligenceError.failed }

        let assembled = Self.assemble(observations)

        #if canImport(FoundationModels)
            if SystemLanguageModel.default.availability == .available {
                if let polished = try? await polish(assembled, observations: observations),
                    AltTextGuidance.looksAcceptable(polished)
                {
                    return polished
                }
            }
        #endif

        return assembled
    }

    /// The fallback, and the floor on quality. Blunt, but never wrong about
    /// what is in the picture, because it only repeats what Vision reported.
    static func assemble(_ observations: Observations) -> String {
        var parts: [String] = []

        if observations.peopleCount == 1 {
            parts.append(String(localized: "One person", comment: "Alt text fragment"))
        } else if observations.peopleCount > 1 {
            parts.append(
                String(
                    localized: "\(observations.peopleCount) people",
                    comment: "Alt text fragment"))
        }

        if !observations.subjects.isEmpty {
            let list = observations.subjects.prefix(3).joined(separator: ", ")
            parts.append(
                parts.isEmpty
                    ? list.localizedCapitalized
                    : String(localized: "with \(list)", comment: "Alt text fragment"))
        }

        var sentence = parts.joined(separator: " ")
        if sentence.isEmpty {
            sentence = String(localized: "A picture", comment: "Alt text fallback")
        }
        if !sentence.hasSuffix(".") { sentence += "." }

        if !observations.recognisedText.isEmpty {
            let quoted = observations.recognisedText.prefix(3).joined(separator: " ")
            sentence += " "
            sentence += String(
                localized: "Text reads: \(quoted).", comment: "Alt text fragment for text in image")
        }

        return String(sentence.prefix(AltTextGuidance.maximumCharacters))
    }

    #if canImport(FoundationModels)
        private func polish(_ draft: String, observations: Observations) async throws -> String {
            let facts = """
                Things detected: \(observations.subjects.joined(separator: ", "))
                People detected: \(observations.peopleCount)
                Text detected: \(observations.recognisedText.prefix(5).joined(separator: " | "))
                """

            let session = LanguageModelSession(
                instructions: AltTextGuidance.instructions + """

                    You are given a list of things a vision system detected in a photograph. \
                    You cannot see the photograph. Write the alt text from the list alone. \
                    Do not add anything that is not in the list. If the list mentions people, \
                    say how many and nothing else about them.
                    """)

            let response = try await session.respond(to: facts)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    #endif
}
