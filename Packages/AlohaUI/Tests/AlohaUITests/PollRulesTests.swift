// SPDX-License-Identifier: MIT

import AlohaModels
import Testing

@testable import AlohaUI

private func limits(
    options: Int = 4, characters: Int = 50, min: Double = 300, max: Double = 2_629_746
) -> ServerLimits {
    var limits = ServerLimits.mastodonDefaults
    limits.maxPollOptions = options
    limits.maxPollOptionCharacters = characters
    limits.minPollExpiration = min
    limits.maxPollExpiration = max
    return limits
}

@Suite("Poll rules")
struct PollRulesTests {
    @Test("Five minutes to seven days, narrowed to the server's bounds")
    func durations() {
        #expect(PollRules.durations(within: limits()) == PollRules.standardDurations)
        // A server that caps polls at a day offers nothing longer.
        #expect(PollRules.durations(within: limits(max: 86_400)).last == 86_400)
        // Nor anything shorter than its minimum.
        #expect(PollRules.durations(within: limits(min: 3_600)).first == 3_600)
        // Bounds no standard step fits: the bounds themselves.
        #expect(PollRules.durations(within: limits(min: 100, max: 200)) == [100, 200])
    }

    @Test("A duration the server would refuse lands on the closest it accepts")
    func closest() {
        #expect(PollRules.closestDuration(to: 86_400, within: limits(max: 3_600)) == 3_600)
        #expect(PollRules.closestDuration(to: 60, within: limits()) == 300)
        #expect(PollRules.closestDuration(to: 86_400, within: limits()) == 86_400)
    }

    @Test("Choices are held to the server's count and length")
    func problems() {
        let server = limits(options: 3, characters: 5)
        // An untouched poll is no poll, and blocks nothing.
        #expect(PollRules.problem(options: ["", ""], limits: server) == nil)
        #expect(PollRules.problem(options: ["yes", ""], limits: server) == .tooFewChoices)
        #expect(PollRules.problem(options: ["yes", "no"], limits: server) == nil)
        #expect(
            PollRules.problem(options: ["yes", "no", "maybe", "never"], limits: server)
                == .tooManyChoices(3))
        #expect(
            PollRules.problem(options: ["yes", "absolutely"], limits: server)
                == .choiceTooLong(5))
        #expect(PollRules.remaining(in: "absolutely", limits: server) == -5)
    }
}
