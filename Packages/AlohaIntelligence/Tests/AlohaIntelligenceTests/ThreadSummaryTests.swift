// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaIntelligence

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Records the calls a summary makes, so a test can see the chunking.
private actor Calls {
    var prompts: [(instructions: String, prompt: String)] = []
    func record(_ instructions: String, _ prompt: String) { prompts.append((instructions, prompt)) }
}

@Suite("Thread summary")
struct ThreadSummaryTests {
    /// One token per character keeps the arithmetic readable.
    private func summariser(budget: Int, calls: Calls) -> ThreadSummariser {
        ThreadSummariser(
            budget: budget,
            measure: { $0.count },
            respond: { instructions, prompt in
                await calls.record(instructions, prompt)
                return "S\(prompt.count)"
            })
    }

    @Test("A thread that fits is summarised in one call")
    func fitsInOneCall() async throws {
        let calls = Calls()
        let result = try await summariser(budget: 100, calls: calls)
            .summarise(["aaaa", "bbbb", "cccc"])
        let prompts = await calls.prompts
        #expect(prompts.count == 1)
        #expect(prompts[0].instructions == ThreadSummariser.threadInstructions)
        #expect(prompts[0].prompt == "aaaa\n\nbbbb\n\ncccc")
        #expect(result == "S16")
    }

    /// docs/10 §5: longer threads are summarised in chunks and the chunk
    /// summaries summarised.
    @Test("A long thread is summarised in parts and the parts combined")
    func chunksAndCombines() async throws {
        let calls = Calls()
        let passages = Array(repeating: String(repeating: "x", count: 40), count: 5)
        _ = try await summariser(budget: 100, calls: calls).summarise(passages)
        let prompts = await calls.prompts
        // Two passages (40 + 2 + 40) fit a chunk of 100, a third does not.
        let parts = prompts.filter { $0.instructions == ThreadSummariser.partInstructions }
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { $0.prompt.count <= 100 })
        #expect(prompts.last?.instructions == ThreadSummariser.combineInstructions)
    }

    @Test("Every chunk stays within the budget")
    func packRespectsBudget() async throws {
        let calls = Calls()
        let passages = (1...30).map { String(repeating: "y", count: $0 * 3) }
        let chunks = try await summariser(budget: 120, calls: calls).pack(passages)
        #expect(chunks.allSatisfy { $0.count <= 120 })
        // Nothing is lost on the way: every passage is in some chunk.
        #expect(chunks.joined(separator: "\n\n") == passages.joined(separator: "\n\n"))
    }

    @Test("A passage longer than the budget is cut, not dropped")
    func overlongPassageIsTruncated() async throws {
        let calls = Calls()
        let chunks = try await summariser(budget: 50, calls: calls)
            .pack([String(repeating: "z", count: 500)])
        #expect(chunks.count == 1)
        #expect(chunks[0].count <= 50)
        #expect(chunks[0].hasPrefix("zzz"))
    }

    @Test("An empty thread is a failure, not an empty summary")
    func emptyThread() async {
        let calls = Calls()
        await #expect(throws: IntelligenceError.failed) {
            try await summariser(budget: 100, calls: calls).summarise(["", "  "])
        }
    }

    @Test("The budget leaves room for the instructions and the answer")
    func budgetArithmetic() {
        #expect(
            ThreadSummariser.budget(contextSize: 4096, instructionsCost: 60)
                == 4096 - 60 - ThreadSummariser.responseReserve)
        // A context reported as tiny still leaves something to work with.
        #expect(ThreadSummariser.budget(contextSize: 100, instructionsCost: 60) == 256)
    }

    @Test("The fallback estimate errs high for Latin and CJK text")
    func estimateIsConservative() {
        // About four characters a token in English: the estimate says more.
        let english = "The quick brown fox jumps over the lazy dog again and again."
        #expect(ThreadSummariser.estimatedTokens(english) >= english.count / 4)
        // About a token a character in Japanese: the estimate says as many.
        let japanese = "今日はとても良い天気ですね"
        #expect(ThreadSummariser.estimatedTokens(japanese) >= japanese.count)
    }
}

@Suite("Intelligence errors")
struct IntelligenceErrorTests {
    @Test("Cancellation is its own outcome, not a refusal")
    func cancellation() {
        #expect(IntelligenceError.classify(CancellationError()) == .cancelled)
    }

    @Test("A known error passes through unchanged")
    func passthrough() {
        #expect(IntelligenceError.classify(IntelligenceError.tooLong) == .tooLong)
    }

    @Test("Anything unrecognised is a plain failure")
    func unknown() {
        struct Other: Error {}
        #expect(IntelligenceError.classify(Other()) == .failed)
    }

    #if canImport(FoundationModels)
        @Test("A context overflow and a guardrail are told apart")
        func modelErrors() {
            let overflow = LanguageModelError.contextSizeExceeded(
                .init(contextSize: 4096, tokenCount: 5000, debugDescription: "too long"))
            #expect(IntelligenceError.classify(overflow) == .contextExceeded)
            let guardrail = LanguageModelError.guardrailViolation(
                .init(debugDescription: "guardrail"))
            #expect(IntelligenceError.classify(guardrail) == .refused)
            let assets = SystemLanguageModel.Error.assetsUnavailable(
                .init(debugDescription: "downloading"))
            #expect(IntelligenceError.classify(assets) == .modelUnavailable)
        }
    #endif
}
