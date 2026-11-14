// SPDX-License-Identifier: MIT

import Foundation

/// Fits a thread into the on-device model's context, and summarises one that
/// does not fit in parts (docs/10 §5).
///
/// The model's context is a few thousand tokens. A long thread used to be cut
/// at sixty posts and handed over whole, and a thread whose sixty posts were
/// still too long failed with the same "refused" a guardrail gets. Here every
/// passage is measured, the passages are packed into chunks that fit, each
/// chunk is summarised, and the chunk summaries are summarised in turn until
/// one is left.
///
/// Pure apart from the two closures, so the packing is testable without the
/// model: `measure` answers a token count, `respond` answers the model's text.
struct ThreadSummariser: Sendable {
    /// Tokens a chunk may use: the context minus the instructions and the
    /// room kept for the answer.
    let budget: Int
    let measure: @Sendable (String) async throws -> Int
    let respond: @Sendable (_ instructions: String, _ prompt: String) async throws -> String

    /// A thread longer than this many chunks is summarised from its opening
    /// chunks only: each chunk is a full model call on the device, and a
    /// summary that takes minutes is one nobody waits for.
    static let maximumChunks = 12
    /// Between passages in a chunk; also what each join costs in tokens, at
    /// most.
    static let separator = "\n\n"
    static let separatorCost = 2
    /// Kept free for the model's answer in every call.
    static let responseReserve = 512

    static let threadInstructions = """
        Summarise a conversation for someone deciding whether to read it. \
        Two or three sentences. Neutral. Do not invent anything that is not there.
        """
    static let partInstructions = """
        Summarise this part of a longer conversation in two or three sentences. \
        Keep who said what. Neutral. Do not invent anything that is not there.
        """
    static let combineInstructions = """
        These are summaries of consecutive parts of one conversation, in order. \
        Combine them into one summary of the whole conversation for someone deciding \
        whether to read it. Two or three sentences. Neutral. Do not invent anything.
        """

    /// The tokens a chunk may use, given the model's context size and what
    /// the instructions cost. Never below a floor that leaves something to
    /// summarise, so a mis-reported context cannot stop the feature outright.
    static func budget(contextSize: Int, instructionsCost: Int) -> Int {
        max(256, contextSize - instructionsCost - responseReserve)
    }

    /// A count that errs high for every script: Latin text runs about four
    /// bytes a token, CJK about three bytes a character and a token each.
    /// Used where the framework cannot be asked.
    static func estimatedTokens(_ text: String) -> Int {
        max(1, text.utf8.count / 3)
    }

    func summarise(_ passages: [String]) async throws -> String {
        let passages = passages.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !passages.isEmpty else { throw IntelligenceError.failed }

        let chunks = try await pack(passages)
        if chunks.count == 1 {
            return try await respond(Self.threadInstructions, chunks[0])
        }

        var summaries: [String] = []
        for chunk in chunks.prefix(Self.maximumChunks) {
            try Task.checkCancellation()
            summaries.append(try await respond(Self.partInstructions, chunk))
        }
        return try await combine(summaries)
    }

    /// Summaries are short, so each round leaves fewer than it started with;
    /// the depth bound is a guard against a model that answers at length.
    private func combine(_ summaries: [String], depth: Int = 0) async throws -> String {
        try Task.checkCancellation()
        if summaries.count == 1 { return summaries[0] }
        let chunks = try await pack(summaries)
        if chunks.count == 1 || depth >= 3 {
            return try await respond(Self.combineInstructions, chunks[0])
        }
        var next: [String] = []
        for chunk in chunks {
            try Task.checkCancellation()
            next.append(try await respond(Self.combineInstructions, chunk))
        }
        return try await combine(next, depth: depth + 1)
    }

    /// Consecutive passages, packed greedily into chunks that each fit the
    /// budget. A passage that alone exceeds it is cut to fit rather than
    /// dropped: the opening of a very long post still says what it is about.
    func pack(_ passages: [String]) async throws -> [String] {
        var chunks: [String] = []
        var current: [String] = []
        var used = 0

        for passage in passages {
            try Task.checkCancellation()
            var text = passage
            var cost = try await measure(text)
            if cost > budget {
                text = Self.truncate(text, cost: cost, budget: budget)
                cost = budget
            }
            let joined = current.isEmpty ? cost : used + Self.separatorCost + cost
            if joined > budget, !current.isEmpty {
                chunks.append(current.joined(separator: Self.separator))
                current = [text]
                used = cost
            } else {
                current.append(text)
                used = joined
            }
        }
        if !current.isEmpty { chunks.append(current.joined(separator: Self.separator)) }
        return chunks
    }

    /// The opening of a passage, in proportion to how far over it is, with a
    /// tenth kept spare because tokens are not spread evenly over characters.
    static func truncate(_ text: String, cost: Int, budget: Int) -> String {
        guard cost > budget, cost > 0 else { return text }
        let ratio = Double(budget) / Double(cost) * 0.9
        let keep = max(1, Int(Double(text.count) * ratio))
        return String(text.prefix(keep)) + "…"
    }
}
